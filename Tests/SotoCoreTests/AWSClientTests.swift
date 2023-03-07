//===----------------------------------------------------------------------===//
//
// This source file is part of the Soto for AWS open source project
//
// Copyright (c) 2017-2022 the Soto project authors
// Licensed under Apache License v2.0
//
// See LICENSE.txt for license information
// See CONTRIBUTORS.txt for the list of Soto project authors
//
// SPDX-License-Identifier: Apache-2.0
//
//===----------------------------------------------------------------------===//

import AsyncHTTPClient
import Foundation
import Logging
import NIOConcurrencyHelpers
import NIOCore
import NIOFoundationCompat
import NIOHTTP1
import NIOPosix
@testable import SotoCore
import SotoTestUtils
import SotoXML
import XCTest
#if compiler(>=5.6)
@preconcurrency import Atomics
#else
import Atomics
#endif

class AWSClientTests: XCTestCase {
    func testGetCredential() {
        let client = createAWSClient(credentialProvider: .static(accessKeyId: "key", secretAccessKey: "secret"))
        defer {
            XCTAssertNoThrow(try client.syncShutdown())
        }

        do {
            let credentialForSignature = try client.getCredential(on: client.eventLoopGroup.next(), logger: TestEnvironment.logger).wait()
            XCTAssertEqual(credentialForSignature.accessKeyId, "key")
            XCTAssertEqual(credentialForSignature.secretAccessKey, "secret")
        } catch {
            XCTFail(error.localizedDescription)
        }
    }

    // this test only really works on Linux as it requires the MetaDataService. On mac it will just pass automatically
    func testExpiredCredential() {
        let client = createAWSClient()
        defer {
            XCTAssertNoThrow(try client.syncShutdown())
        }

        do {
            let credentials = try client.getCredential(on: client.eventLoopGroup.next(), logger: TestEnvironment.logger).wait()
            print(credentials)
        } catch let error as CredentialProviderError where error == .noProvider {
            // credentials request should fail. One possible error is a connectTimerout
        } catch {
            XCTFail("Unexpected error \(error)")
        }
    }

    func testShutdown() {
        let httpClient = HTTPClient(eventLoopGroupProvider: .createNew)
        defer { XCTAssertNoThrow(try httpClient.syncShutdown()) }

        let client = createAWSClient(httpClientProvider: .shared(httpClient))
        let promise: EventLoopPromise<Void> = httpClient.eventLoopGroup.next().makePromise()
        client.shutdown { error in
            if let error = error {
                promise.completeWith(.failure(error))
            } else {
                promise.completeWith(.success(()))
            }
        }
        XCTAssertNoThrow(try promise.futureResult.wait())
    }

    func testShutdownWithEventLoop() {
        let eventLoopGroup = MultiThreadedEventLoopGroup(numberOfThreads: 1)
        defer { XCTAssertNoThrow(try eventLoopGroup.syncShutdownGracefully()) }
        let eventLoop = eventLoopGroup.next()

        let client = createAWSClient(httpClientProvider: .createNewWithEventLoopGroup(eventLoopGroup))
        let promise: EventLoopPromise<Void> = eventLoop.makePromise()
        client.shutdown { error in
            if let error = error {
                promise.completeWith(.failure(error))
            } else {
                promise.completeWith(.success(()))
            }
        }
        XCTAssertNoThrow(try promise.futureResult.wait())
    }

    func testHeadersAreWritten() {
        struct Input: AWSEncodableShape {
            let content: String
        }
        let awsServer = AWSTestServer(serviceProtocol: .json)
        let elg = MultiThreadedEventLoopGroup(numberOfThreads: 1)
        let httpClient = HTTPClient(eventLoopGroupProvider: .shared(elg))
        defer {
            try? awsServer.stop()
            try? httpClient.syncShutdown()
            try? elg.syncShutdownGracefully()
        }
        let config = createServiceConfig(
            serviceProtocol: .json(version: "1.1"),
            endpoint: awsServer.address
        )
        let client = createAWSClient(
            credentialProvider: .static(accessKeyId: "foo", secretAccessKey: "bar"),
            httpClientProvider: .shared(httpClient)
        )
        defer {
            XCTAssertNoThrow(try client.syncShutdown())
        }
        let response: EventLoopFuture<AWSTestServer.HTTPBinResponse> = client.execute(
            operation: "test",
            path: "/",
            httpMethod: .POST,
            serviceConfig: config,
            input: Input(content: "test"),
            logger: TestEnvironment.logger
        )

        XCTAssertNoThrow(try awsServer.httpBin())
        var httpBinResponse: AWSTestServer.HTTPBinResponse?
        XCTAssertNoThrow(httpBinResponse = try response.wait())
        let httpHeaders = httpBinResponse.map { HTTPHeaders($0.headers.map { ($0, $1) }) }

        XCTAssertEqual(httpHeaders?["content-length"].first, "18")
        XCTAssertEqual(httpHeaders?["content-type"].first, "application/x-amz-json-1.1")
        XCTAssertNotNil(httpHeaders?["authorization"].first)
        XCTAssertNotNil(httpHeaders?["x-amz-date"].first)
        XCTAssertEqual(httpHeaders?["user-agent"].first, "Soto/6.0")
        XCTAssertEqual(httpHeaders?["host"].first, "localhost:\(awsServer.serverPort)")
    }

    func testClientNoInputNoOutput() {
        do {
            let awsServer = AWSTestServer(serviceProtocol: .json)
            let config = createServiceConfig(serviceProtocol: .json(version: "1.1"), endpoint: awsServer.address)
            let client = createAWSClient(credentialProvider: .empty, middlewares: [AWSLoggingMiddleware()])
            defer {
                XCTAssertNoThrow(try client.syncShutdown())
                XCTAssertNoThrow(try awsServer.stop())
            }
            let response = client.execute(operation: "test", path: "/", httpMethod: .POST, serviceConfig: config, logger: TestEnvironment.logger)

            try awsServer.processRaw { _ in
                let response = AWSTestServer.Response(httpStatus: .ok, headers: [:], body: nil)
                return .result(response)
            }

            try response.wait()
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testClientWithInputNoOutput() {
        enum InputEnum: String, Codable {
            case first
            case second
        }
        struct Input: AWSEncodableShape & Decodable {
            let e: InputEnum
            let i: [Int64]
        }

        do {
            let awsServer = AWSTestServer(serviceProtocol: .json)
            let config = createServiceConfig(serviceProtocol: .json(version: "1.1"), endpoint: awsServer.address)
            let client = createAWSClient(credentialProvider: .empty, middlewares: [AWSLoggingMiddleware()])
            defer {
                XCTAssertNoThrow(try client.syncShutdown())
                XCTAssertNoThrow(try awsServer.stop())
            }
            let input = Input(e: .second, i: [1, 2, 4, 8])
            let response = client.execute(operation: "test", path: "/", httpMethod: .POST, serviceConfig: config, input: input, logger: TestEnvironment.logger)

            try awsServer.processRaw { request in
                let receivedInput = try JSONDecoder().decode(Input.self, from: request.body)
                XCTAssertEqual(receivedInput.e, .second)
                XCTAssertEqual(receivedInput.i, [1, 2, 4, 8])
                let response = AWSTestServer.Response(httpStatus: .ok, headers: [:], body: nil)
                return .result(response)
            }

            try response.wait()
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testClientNoInputWithOutput() {
        struct Output: AWSDecodableShape & Encodable {
            let s: String
            let i: Int64
        }
        do {
            let eventLoopGroup = MultiThreadedEventLoopGroup(numberOfThreads: 1)
            defer { XCTAssertNoThrow(try eventLoopGroup.syncShutdownGracefully()) }
            let awsServer = AWSTestServer(serviceProtocol: .json)
            let config = createServiceConfig(serviceProtocol: .json(version: "1.1"), endpoint: awsServer.address)
            let client = createAWSClient(
                credentialProvider: .empty,
                httpClientProvider: .createNewWithEventLoopGroup(eventLoopGroup)
            )
            defer {
                XCTAssertNoThrow(try client.syncShutdown())
                XCTAssertNoThrow(try awsServer.stop())
            }
            let response: EventLoopFuture<Output> = client.execute(operation: "test", path: "/", httpMethod: .POST, serviceConfig: config, logger: TestEnvironment.logger)

            try awsServer.processRaw { _ in
                let output = Output(s: "TestOutputString", i: 547)
                let byteBuffer = try JSONEncoder().encodeAsByteBuffer(output, allocator: ByteBufferAllocator())
                let response = AWSTestServer.Response(httpStatus: .ok, headers: [:], body: byteBuffer)
                return .result(response)
            }

            let output = try response.wait()

            XCTAssertEqual(output.s, "TestOutputString")
            XCTAssertEqual(output.i, 547)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testRequestStreaming(config: AWSServiceConfig, client: AWSClient, server: AWSTestServer, bufferSize: Int, blockSize: Int) throws {
        struct Input: AWSEncodableShape & AWSShapeWithPayload {
            static var _payloadPath: String = "payload"
            static var _options: AWSShapeOptions = [.allowStreaming, .rawPayload]
            let payload: AWSPayload
            private enum CodingKeys: CodingKey {}
        }
        let data = createRandomBuffer(45, 9182, size: bufferSize)
        var byteBuffer = ByteBufferAllocator().buffer(capacity: data.count)
        byteBuffer.writeBytes(data)

        let payload = AWSPayload.stream(size: bufferSize) { eventLoop in
            let size = min(blockSize, byteBuffer.readableBytes)
            // don't ask for 0 bytes
            if size == 0 {
                return eventLoop.makeSucceededFuture(.end)
            }
            let buffer = byteBuffer.readSlice(length: size)!
            return eventLoop.makeSucceededFuture(.byteBuffer(buffer))
        }
        let input = Input(payload: payload)
        let response = client.execute(operation: "test", path: "/", httpMethod: .POST, serviceConfig: config, input: input, logger: TestEnvironment.logger)

        try? server.processRaw { request in
            let bytes = request.body.getBytes(at: 0, length: request.body.readableBytes)
            XCTAssertEqual(bytes, data)
            let response = AWSTestServer.Response(httpStatus: .ok, headers: [:], body: nil)
            return .result(response)
        }

        try response.wait()
    }

    func testRequestStreaming() {
        let awsServer = AWSTestServer(serviceProtocol: .json)
        let httpClient = HTTPClient(eventLoopGroupProvider: .createNew)
        let config = createServiceConfig(endpoint: awsServer.address)
        let client = createAWSClient(credentialProvider: .empty, httpClientProvider: .shared(httpClient))
        defer {
            XCTAssertNoThrow(try awsServer.stop())
            XCTAssertNoThrow(try client.syncShutdown())
            XCTAssertNoThrow(try httpClient.syncShutdown())
        }

        XCTAssertNoThrow(try self.testRequestStreaming(config: config, client: client, server: awsServer, bufferSize: 128 * 1024, blockSize: 16 * 1024))
        XCTAssertNoThrow(try self.testRequestStreaming(config: config, client: client, server: awsServer, bufferSize: 128 * 1024, blockSize: 17 * 1024))
        XCTAssertNoThrow(try self.testRequestStreaming(config: config, client: client, server: awsServer, bufferSize: 18 * 1024, blockSize: 47 * 1024))
    }

    func testRequestS3Streaming() {
        let awsServer = AWSTestServer(serviceProtocol: .json)
        let httpClient = HTTPClient(eventLoopGroupProvider: .createNew)
        let config = createServiceConfig(service: "s3", endpoint: awsServer.address)
        let client = createAWSClient(credentialProvider: .static(accessKeyId: "foo", secretAccessKey: "bar"), httpClientProvider: .shared(httpClient))
        defer {
            XCTAssertNoThrow(try client.syncShutdown())
            XCTAssertNoThrow(try awsServer.stop())
            XCTAssertNoThrow(try httpClient.syncShutdown())
        }

        XCTAssertNoThrow(try self.testRequestStreaming(config: config, client: client, server: awsServer, bufferSize: 128 * 1024, blockSize: 16 * 1024))
        XCTAssertNoThrow(try self.testRequestStreaming(config: config, client: client, server: awsServer, bufferSize: 192 * 1024, blockSize: 128 * 1024))
        XCTAssertNoThrow(try self.testRequestStreaming(config: config, client: client, server: awsServer, bufferSize: 81 * 1024, blockSize: 16 * 1024))
        XCTAssertNoThrow(try self.testRequestStreaming(config: config, client: client, server: awsServer, bufferSize: 128 * 1024, blockSize: S3ChunkedStreamReader.bufferSize))
        XCTAssertNoThrow(try self.testRequestStreaming(config: config, client: client, server: awsServer, bufferSize: 130 * 1024, blockSize: S3ChunkedStreamReader.bufferSize))
        XCTAssertNoThrow(try self.testRequestStreaming(config: config, client: client, server: awsServer, bufferSize: 128 * 1024, blockSize: 17 * 1024))
        XCTAssertNoThrow(try self.testRequestStreaming(config: config, client: client, server: awsServer, bufferSize: 68 * 1024, blockSize: 67 * 1024))
        XCTAssertNoThrow(try self.testRequestStreaming(config: config, client: client, server: awsServer, bufferSize: 65537, blockSize: 65537))
        XCTAssertNoThrow(try self.testRequestStreaming(config: config, client: client, server: awsServer, bufferSize: 65552, blockSize: 65552))
    }

    func testRequestStreamingAvoidStackOverflow() {
        let awsServer = AWSTestServer(serviceProtocol: .json)
        let httpClient = HTTPClient(eventLoopGroupProvider: .createNew)
        let config = createServiceConfig(service: "s3", endpoint: awsServer.address)
        let client = createAWSClient(credentialProvider: .static(accessKeyId: "foo", secretAccessKey: "bar"), httpClientProvider: .shared(httpClient))
        defer {
            XCTAssertNoThrow(try client.syncShutdown())
            XCTAssertNoThrow(try awsServer.stop())
            XCTAssertNoThrow(try httpClient.syncShutdown())
        }

        XCTAssertNoThrow(try self.testRequestStreaming(config: config, client: client, server: awsServer, bufferSize: 16 * 1024, blockSize: 8))
    }

    func testRequestStreamingWithPayload(_ payload: AWSPayload) throws {
        struct Input: AWSEncodableShape & AWSShapeWithPayload {
            static var _payloadPath: String = "payload"
            static var _options: AWSShapeOptions = [.allowStreaming]
            let payload: AWSPayload
            private enum CodingKeys: CodingKey {}
        }

        let awsServer = AWSTestServer(serviceProtocol: .json)
        let httpClient = HTTPClient(eventLoopGroupProvider: .createNew)
        let config = createServiceConfig(endpoint: awsServer.address)
        let client = createAWSClient(credentialProvider: .empty, httpClientProvider: .shared(httpClient))
        defer {
            // ignore error
            try? awsServer.stop()
            XCTAssertNoThrow(try client.syncShutdown())
            XCTAssertNoThrow(try httpClient.syncShutdown())
        }
        let input = Input(payload: payload)
        let response = client.execute(operation: "test", path: "/", httpMethod: .POST, serviceConfig: config, input: input, logger: TestEnvironment.logger)
        try response.wait()
    }

    func testRequestStreamingTooMuchData() {
        // set up stream of 8 bytes but supply more than that
        let payload = AWSPayload.stream(size: 8) { eventLoop in
            var buffer = ByteBufferAllocator().buffer(capacity: 0)
            buffer.writeString("String longer than 8 bytes")
            return eventLoop.makeSucceededFuture(.byteBuffer(buffer))
        }
        XCTAssertThrowsError(try self.testRequestStreamingWithPayload(payload)) { error in
            guard let error = error as? AWSClient.ClientError, error == .tooMuchData else {
                XCTFail()
                return
            }
        }
    }

    func testRequestStreamingNotEnoughData() {
        var byteBuffer = ByteBufferAllocator().buffer(staticString: "Buffer")
        let payload = AWSPayload.stream(size: byteBuffer.readableBytes + 1) { eventLoop in
            let size = byteBuffer.readableBytes
            if size == 0 {
                return eventLoop.makeSucceededFuture(.end)
            }
            let buffer = byteBuffer.readSlice(length: size)!
            return eventLoop.makeSucceededFuture(.byteBuffer(buffer))
        }
        XCTAssertThrowsError(try self.testRequestStreamingWithPayload(payload)) { error in
            guard let error = error as? AWSClient.ClientError, error == .notEnoughData else {
                XCTFail()
                return
            }
        }
    }

    func testRequestStreamingFile() {
        struct Input: AWSEncodableShape & AWSShapeWithPayload {
            static var _payloadPath: String = "payload"
            static var _options: AWSShapeOptions = [.allowStreaming]
            let payload: AWSPayload
            private enum CodingKeys: CodingKey {}
        }

        let awsServer = AWSTestServer(serviceProtocol: .json)
        let httpClient = HTTPClient(eventLoopGroupProvider: .createNew)
        let config = createServiceConfig(endpoint: awsServer.address)
        let client = createAWSClient(credentialProvider: .empty, httpClientProvider: .shared(httpClient))
        defer {
            XCTAssertNoThrow(try awsServer.stop())
            XCTAssertNoThrow(try client.syncShutdown())
            XCTAssertNoThrow(try httpClient.syncShutdown())
        }
        do {
            let bufferSize = 208 * 1024
            let data = Data(createRandomBuffer(45, 9182, size: bufferSize))
            let filename = "testRequestStreamingFile"
            let fileURL = URL(fileURLWithPath: filename)
            try data.write(to: fileURL)
            defer {
                XCTAssertNoThrow(try FileManager.default.removeItem(at: fileURL))
            }

            let threadPool = NIOThreadPool(numberOfThreads: 3)
            threadPool.start()
            let fileIO = NonBlockingFileIO(threadPool: threadPool)
            let fileHandle = try fileIO.openFile(path: filename, mode: .read, eventLoop: httpClient.eventLoopGroup.next()).wait()
            defer {
                XCTAssertNoThrow(try fileHandle.close())
                XCTAssertNoThrow(try threadPool.syncShutdownGracefully())
            }

            let input = Input(payload: .fileHandle(fileHandle, size: bufferSize, fileIO: fileIO) { size in print(size) })
            let response = client.execute(operation: "test", path: "/", httpMethod: .POST, serviceConfig: config, input: input, logger: TestEnvironment.logger)

            try awsServer.processRaw { request in
                XCTAssertNil(request.headers["transfer-encoding"])
                XCTAssertEqual(request.headers["Content-Length"], bufferSize.description)
                let requestData = request.body.getData(at: 0, length: request.body.readableBytes)
                XCTAssertEqual(requestData, data)
                let response = AWSTestServer.Response(httpStatus: .ok, headers: [:], body: nil)
                return .result(response)
            }

            try response.wait()
        } catch let error as AWSClient.ClientError where error == .tooMuchData {
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testRequestChunkedStreaming() {
        struct Input: AWSEncodableShape & AWSShapeWithPayload {
            static var _payloadPath: String = "payload"
            static var _options: AWSShapeOptions = [.allowStreaming, .allowChunkedStreaming, .rawPayload]
            let payload: AWSPayload
            private enum CodingKeys: CodingKey {}
        }

        let awsServer = AWSTestServer(serviceProtocol: .json)
        let httpClient = HTTPClient(eventLoopGroupProvider: .createNew)
        let config = createServiceConfig(endpoint: awsServer.address)
        let client = createAWSClient(credentialProvider: .empty, httpClientProvider: .shared(httpClient))
        defer {
            XCTAssertNoThrow(try awsServer.stop())
            XCTAssertNoThrow(try client.syncShutdown())
            XCTAssertNoThrow(try httpClient.syncShutdown())
        }
        do {
            // supply buffer in 16k blocks
            let bufferSize = 145 * 1024
            let blockSize = 16 * 1024
            let data = createRandomBuffer(45, 9182, size: bufferSize)
            var byteBuffer = ByteBufferAllocator().buffer(capacity: bufferSize)
            byteBuffer.writeBytes(data)

            let payload = AWSPayload.stream { eventLoop in
                let size = min(blockSize, byteBuffer.readableBytes)
                if size == 0 {
                    return eventLoop.makeSucceededFuture(.end)
                } else {
                    return eventLoop.makeSucceededFuture(.byteBuffer(byteBuffer.readSlice(length: size)!))
                }
            }
            let input = Input(payload: payload)
            let response = client.execute(operation: "test", path: "/", httpMethod: .POST, serviceConfig: config, input: input, logger: TestEnvironment.logger)

            try awsServer.processRaw { request in
                let bytes = request.body.getBytes(at: 0, length: request.body.readableBytes)
                XCTAssertTrue(bytes == data)
                let response = AWSTestServer.Response(httpStatus: .ok, headers: [:], body: nil)
                return .result(response)
            }

            try response.wait()
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testProvideHTTPClient() {
        do {
            // By default AsyncHTTPClient will follow redirects. This test creates an HTTP client that doesn't follow redirects and
            // provides it to AWSClient
            let awsServer = AWSTestServer(serviceProtocol: .json)
            let httpClientConfig = AsyncHTTPClient.HTTPClient.Configuration(redirectConfiguration: .init(.disallow))
            let httpClient = AsyncHTTPClient.HTTPClient(eventLoopGroupProvider: .createNew, configuration: httpClientConfig)
            let config = createServiceConfig(serviceProtocol: .json(version: "1.1"), endpoint: awsServer.address)
            let client = createAWSClient(credentialProvider: .empty, httpClientProvider: .shared(httpClient))
            defer {
                XCTAssertNoThrow(try awsServer.stop())
                XCTAssertNoThrow(try client.syncShutdown())
                XCTAssertNoThrow(try httpClient.syncShutdown())
            }
            let response = client.execute(operation: "test", path: "/", httpMethod: .POST, serviceConfig: config, logger: TestEnvironment.logger)

            try awsServer.processRaw { _ in
                let response = AWSTestServer.Response(httpStatus: .temporaryRedirect, headers: ["Location": awsServer.address], body: nil)
                return .result(response)
            }

            try response.wait()
            XCTFail("Shouldn't get here as the provided client doesn't follow redirects")
        } catch let error as AWSRawError {
            XCTAssertEqual(error.context.message, "Unhandled Error")
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testServerError() {
        do {
            let httpClient = AsyncHTTPClient.HTTPClient(eventLoopGroupProvider: .createNew)
            let awsServer = AWSTestServer(serviceProtocol: .json)
            let config = createServiceConfig(serviceProtocol: .json(version: "1.1"), endpoint: awsServer.address)
            let client = createAWSClient(credentialProvider: .empty, retryPolicy: .exponential(base: .milliseconds(200)), httpClientProvider: .shared(httpClient))
            defer {
                XCTAssertNoThrow(try awsServer.stop())
                XCTAssertNoThrow(try client.syncShutdown())
                XCTAssertNoThrow(try httpClient.syncShutdown())
            }
            let response = client.execute(operation: "test", path: "/", httpMethod: .POST, serviceConfig: config, logger: TestEnvironment.logger)

            var count = 0
            try awsServer.processRaw { _ in
                count += 1
                if count < 5 {
                    return .error(.internal, continueProcessing: true)
                } else {
                    return .result(.ok)
                }
            }

            try response.wait()
        } catch let error as AWSServerError {
            switch error {
            case .internalFailure:
                XCTAssertEqual(error.message, AWSTestServer.ErrorType.internal.message)
            default:
                XCTFail("Unexpected error: \(error)")
            }
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testClientRetry() {
        struct Output: AWSDecodableShape, Encodable {
            let s: String
        }
        do {
            let httpClient = AsyncHTTPClient.HTTPClient(eventLoopGroupProvider: .createNew)
            let awsServer = AWSTestServer(serviceProtocol: .json)
            let config = createServiceConfig(serviceProtocol: .json(version: "1.1"), endpoint: awsServer.address)
            let client = createAWSClient(credentialProvider: .empty, retryPolicy: .jitter(), httpClientProvider: .shared(httpClient))
            defer {
                XCTAssertNoThrow(try awsServer.stop())
                XCTAssertNoThrow(try client.syncShutdown())
                XCTAssertNoThrow(try httpClient.syncShutdown())
            }
            let response: EventLoopFuture<Output> = client.execute(
                operation: "test",
                path: "/",
                httpMethod: .POST,
                serviceConfig: config,
                logger: TestEnvironment.logger
            )

            var count = 0
            try awsServer.processRaw { _ in
                count += 1
                if count < 3 {
                    return .error(.notImplemented, continueProcessing: true)
                } else {
                    let output = Output(s: "TestOutputString")
                    let byteBuffer = try JSONEncoder().encodeAsByteBuffer(output, allocator: ByteBufferAllocator())
                    let response = AWSTestServer.Response(httpStatus: .ok, headers: [:], body: byteBuffer)
                    return .result(response)
                }
            }

            let output = try response.wait()

            XCTAssertEqual(output.s, "TestOutputString")
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testCustomRetryPolicy() {
        final class TestRetryPolicy: RetryPolicy {
            static let maxRetries: Int = 3
            let attempt = ManagedAtomic(0)

            init() {}

            func getRetryWaitTime(error: Error, attempt: Int) -> RetryStatus? {
                self.attempt.store(attempt, ordering: .relaxed)
                if attempt < Self.maxRetries { return .retry(wait: .milliseconds(100)) }
                return .dontRetry
            }
        }
        let retryPolicy = TestRetryPolicy()
        do {
            let awsServer = AWSTestServer(serviceProtocol: .json)
            let serverAddress = awsServer.address
            defer { XCTAssertNoThrow(try awsServer.stop()) }
            let eventLoopGroup = MultiThreadedEventLoopGroup(numberOfThreads: 1)
            defer { XCTAssertNoThrow(try eventLoopGroup.syncShutdownGracefully()) }
            let httpClient = AsyncHTTPClient.HTTPClient(eventLoopGroupProvider: .shared(eventLoopGroup))
            defer { XCTAssertNoThrow(try httpClient.syncShutdown()) }
            let config = createServiceConfig(serviceProtocol: .json(version: "1.1"), endpoint: serverAddress)
            let client = createAWSClient(credentialProvider: .empty, retryPolicy: .init(retryPolicy: retryPolicy), httpClientProvider: .shared(httpClient))
            defer { XCTAssertNoThrow(try client.syncShutdown()) }
            let response: EventLoopFuture<Void> = client.execute(
                operation: "test",
                path: "/",
                httpMethod: .POST,
                serviceConfig: config,
                logger: TestEnvironment.logger
            )

            var count = 0
            try awsServer.processRaw { _ in
                count += 1
                if count < 4 {
                    return .error(.serviceUnavailable, continueProcessing: true)
                } else {
                    return .error(.serviceUnavailable, continueProcessing: false)
                }
            }

            try response.wait()
        } catch let error as AWSServerError where error == .serviceUnavailable {
            XCTAssertEqual(retryPolicy.attempt.load(ordering: .relaxed), TestRetryPolicy.maxRetries)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testClientRetryFail() {
        struct Output: AWSDecodableShape, Encodable {
            let s: String
        }
        do {
            let httpClient = AsyncHTTPClient.HTTPClient(eventLoopGroupProvider: .createNew)
            let awsServer = AWSTestServer(serviceProtocol: .json)
            let config = createServiceConfig(serviceProtocol: .json(version: "1.1"), endpoint: awsServer.address)
            let client = createAWSClient(credentialProvider: .empty, retryPolicy: .jitter(), httpClientProvider: .shared(httpClient))
            defer {
                XCTAssertNoThrow(try awsServer.stop())
                XCTAssertNoThrow(try client.syncShutdown())
                XCTAssertNoThrow(try httpClient.syncShutdown())
            }
            let response: EventLoopFuture<Output> = client.execute(
                operation: "test",
                path: "/",
                httpMethod: .POST,
                serviceConfig: config,
                logger: TestEnvironment.logger
            )

            try awsServer.processRaw { _ in
                return .error(.accessDenied, continueProcessing: false)
            }

            let output = try response.wait()

            XCTAssertEqual(output.s, "TestOutputString")
        } catch let error as AWSClientError where error == AWSClientError.accessDenied {
            XCTAssertEqual(error.message, AWSTestServer.ErrorType.accessDenied.message)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    /// verify we are not calling the Retry handler when streaming a request
    func testDontRetryStreamingRequests() {
        final class TestRetryPolicy: RetryPolicy {
            func getRetryWaitTime(error: Error, attempt: Int) -> RetryStatus? {
                XCTFail("This should not be called as streaming has disabled retries")
                return .dontRetry
            }
        }
        struct Input: AWSEncodableShape & AWSShapeWithPayload {
            static var _payloadPath: String = "payload"
            static var _options: AWSShapeOptions = [.allowStreaming, .allowChunkedStreaming, .rawPayload]
            let payload: AWSPayload
            private enum CodingKeys: CodingKey {}
        }
        let retryPolicy = TestRetryPolicy()
        do {
            let httpClient = AsyncHTTPClient.HTTPClient(eventLoopGroupProvider: .createNew)
            let awsServer = AWSTestServer(serviceProtocol: .json)
            let config = createServiceConfig(serviceProtocol: .json(version: "1.1"), endpoint: awsServer.address)
            let client = createAWSClient(credentialProvider: .empty, retryPolicy: .init(retryPolicy: retryPolicy), httpClientProvider: .shared(httpClient))
            defer {
                XCTAssertNoThrow(try awsServer.stop())
                XCTAssertNoThrow(try client.syncShutdown())
                XCTAssertNoThrow(try httpClient.syncShutdown())
            }
            let payload = AWSPayload.stream { eventLoop in return eventLoop.makeSucceededFuture(.end) }
            let input = Input(payload: payload)
            let response: EventLoopFuture<Void> = client.execute(
                operation: "test",
                path: "/",
                httpMethod: .POST,
                serviceConfig: config,
                input: input,
                logger: TestEnvironment.logger
            )
            try awsServer.processRaw { _ in
                return .error(.accessDenied, continueProcessing: false)
            }

            try response.wait()
        } catch let error as AWSClientError where error == .accessDenied {
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testClientResponseEventLoop() {
        do {
            let eventLoopGroup = MultiThreadedEventLoopGroup(numberOfThreads: 5)
            let httpClient = HTTPClient(eventLoopGroupProvider: .shared(eventLoopGroup))
            let awsServer = AWSTestServer(serviceProtocol: .json)
            let config = createServiceConfig(endpoint: awsServer.address)
            let client = createAWSClient(credentialProvider: .empty, httpClientProvider: .shared(httpClient))
            defer {
                XCTAssertNoThrow(try client.syncShutdown())
                XCTAssertNoThrow(try httpClient.syncShutdown())
                XCTAssertNoThrow(try eventLoopGroup.syncShutdownGracefully())
                XCTAssertNoThrow(try awsServer.stop())
            }
            let eventLoop = client.eventLoopGroup.next()
            let response: EventLoopFuture<Void> = client.execute(
                operation: "test",
                path: "/",
                httpMethod: .POST,
                serviceConfig: config,
                logger: TestEnvironment.logger,
                on: eventLoop
            )

            try awsServer.processRaw { _ in
                return .result(.ok)
            }
            XCTAssertTrue(eventLoop === response.eventLoop)

            try response.wait()
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testStreamingResponse() {
        struct Input: AWSEncodableShape {}
        struct Output: AWSDecodableShape & Encodable {
            static let _encoding = [AWSMemberEncoding(label: "test", location: .header("test"))]
            let test: String
        }
        let data = createRandomBuffer(45, 109, size: 128 * 1024)

        do {
            let awsServer = AWSTestServer(serviceProtocol: .json)
            let eventLoopGroup = MultiThreadedEventLoopGroup(numberOfThreads: 5)
            let httpClient = HTTPClient(eventLoopGroupProvider: .shared(eventLoopGroup))
            let config = createServiceConfig(endpoint: awsServer.address)
            let client = createAWSClient(credentialProvider: .empty, httpClientProvider: .shared(httpClient))
            defer {
                XCTAssertNoThrow(try client.syncShutdown())
                XCTAssertNoThrow(try httpClient.syncShutdown())
                XCTAssertNoThrow(try eventLoopGroup.syncShutdownGracefully())
                XCTAssertNoThrow(try awsServer.stop())
            }
            var count = 0
            let response: EventLoopFuture<Output> = client.execute(
                operation: "test",
                path: "/",
                httpMethod: .GET,
                serviceConfig: config,
                input: Input(),
                logger: TestEnvironment.logger
            ) { (payload: ByteBuffer, eventLoop: EventLoop) in
                let payloadSize = payload.readableBytes
                let slice = Data(data[count..<(count + payloadSize)])
                let payloadData = payload.getData(at: 0, length: payload.readableBytes)
                XCTAssertEqual(slice, payloadData)
                count += payloadSize
                return eventLoop.makeSucceededFuture(())
            }

            try awsServer.processRaw { _ in
                var byteBuffer = ByteBufferAllocator().buffer(capacity: 128 * 1024)
                byteBuffer.writeBytes(data)
                let response = AWSTestServer.Response(httpStatus: .ok, headers: ["test": "TestHeader"], body: byteBuffer)
                return .result(response)
            }

            let result = try response.wait()
            XCTAssertEqual(result.test, "TestHeader")
            XCTAssertEqual(count, 128 * 1024)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testStreamingDelegateFinished() {
        struct Input: AWSEncodableShape {}
        struct Output: AWSDecodableShape & Encodable {
            static let _encoding = [AWSMemberEncoding(label: "test", location: .header("test"))]
            let test: String
        }
        let bufferSize = 200 * 1024
        let data = createRandomBuffer(45, 109, size: bufferSize)

        let awsServer = AWSTestServer(serviceProtocol: .json)
        let eventLoopGroup = MultiThreadedEventLoopGroup(numberOfThreads: 5)
        let httpClient = HTTPClient(eventLoopGroupProvider: .shared(eventLoopGroup))
        let config = createServiceConfig(endpoint: awsServer.address)
        let client = createAWSClient(credentialProvider: .empty, httpClientProvider: .shared(httpClient))
        defer {
            XCTAssertNoThrow(try client.syncShutdown())
            XCTAssertNoThrow(try httpClient.syncShutdown())
            XCTAssertNoThrow(try eventLoopGroup.syncShutdownGracefully())
            XCTAssertNoThrow(try awsServer.stop())
        }
        var count = 0
        let lock = NIOLock()
        let response: EventLoopFuture<Output> = client.execute(
            operation: "test",
            path: "/",
            httpMethod: .GET,
            serviceConfig: config,
            input: Input(),
            logger: TestEnvironment.logger
        ) { (_: ByteBuffer, eventLoop: EventLoop) in
            lock.withLock { count += 1 }
            return eventLoop.scheduleTask(in: .milliseconds(200)) {
                lock.withLock { count -= 1 }
            }.futureResult
        }

        XCTAssertNoThrow(try awsServer.processRaw { _ in
            var byteBuffer = ByteBufferAllocator().buffer(capacity: bufferSize)
            byteBuffer.writeBytes(data)
            let response = AWSTestServer.Response(httpStatus: .ok, headers: ["test": "TestHeader"], body: byteBuffer)
            return .result(response)
        })

        XCTAssertNoThrow(_ = try response.wait())
        XCTAssertEqual(count, 0)
    }
}
