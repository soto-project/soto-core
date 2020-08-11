//===----------------------------------------------------------------------===//
//
// This source file is part of the AWSSDKSwift open source project
//
// Copyright (c) 2017-2020 the AWSSDKSwift project authors
// Licensed under Apache License v2.0
//
// See LICENSE.txt for license information
// See CONTRIBUTORS.txt for the list of AWSSDKSwift project authors
//
// SPDX-License-Identifier: Apache-2.0
//
//===----------------------------------------------------------------------===//

import AsyncHTTPClient
@testable import AWSSDKSwiftCore
import AWSTestUtils
import AWSXML
import Logging
import NIO
import NIOConcurrencyHelpers
import NIOFoundationCompat
import NIOHTTP1
import XCTest

class AWSClientTests: XCTestCase {
    func testGetCredential() {
        let client = createAWSClient(credentialProvider: .static(accessKeyId: "key", secretAccessKey: "secret"))
        defer {
            XCTAssertNoThrow(try client.syncShutdown())
        }

        do {
            let credentialForSignature = try client.credentialProvider.getCredential(on: client.eventLoopGroup.next(), logger: TestEnvironment.logger).wait()
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
            let credentials = try client.credentialProvider.getCredential(on: client.eventLoopGroup.next(), logger: TestEnvironment.logger).wait()
            print(credentials)
        } catch let error as CredentialProviderError where error == .noProvider {
            // credentials request should fail. One possible error is a connectTimerout
        } catch {
            XCTFail("Unexpected error \(error)")
        }
    }

    func testShutdown() {
        let eventLoopGroup = MultiThreadedEventLoopGroup(numberOfThreads: 1)
        defer { XCTAssertNoThrow(try eventLoopGroup.syncShutdownGracefully()) }
        let httpClient = HTTPClient(eventLoopGroupProvider: .createNew)
        defer { XCTAssertNoThrow(try httpClient.syncShutdown()) }
        let eventLoop = eventLoopGroup.next()
        // currently only testing with httpClientProvider: .shared(httpClient)
        let client = createAWSClient(httpClientProvider: .shared(httpClient))
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
        let response: EventLoopFuture<AWSTestServer.HTTPBinResponse> = client.execute(operation: "test", path: "/", httpMethod: .POST, config: config, context: TestEnvironment.context)

        XCTAssertNoThrow(try awsServer.httpBin())
        var httpBinResponse: AWSTestServer.HTTPBinResponse?
        XCTAssertNoThrow(httpBinResponse = try response.wait())
        let httpHeaders = httpBinResponse.map { HTTPHeaders($0.headers.map { ($0, $1) }) }

        XCTAssertEqual(httpHeaders?["content-length"].first, "0")
        XCTAssertEqual(httpHeaders?["content-type"].first, "application/x-amz-json-1.1")
        XCTAssertNotNil(httpHeaders?["authorization"].first)
        XCTAssertNotNil(httpHeaders?["x-amz-date"].first)
        XCTAssertEqual(httpHeaders?["user-agent"].first, "AWSSDKSwift/5.0")
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
            let response = client.execute(operation: "test", path: "/", httpMethod: .POST, config: config, context: TestEnvironment.context)

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
            let response = client.execute(operation: "test", path: "/", httpMethod: .POST, input: input, config: config, context: TestEnvironment.context)

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
            let awsServer = AWSTestServer(serviceProtocol: .json)
            let config = createServiceConfig(serviceProtocol: .json(version: "1.1"), endpoint: awsServer.address)
            let client = createAWSClient(credentialProvider: .empty, middlewares: [AWSLoggingMiddleware()])
            defer {
                XCTAssertNoThrow(try client.syncShutdown())
                XCTAssertNoThrow(try awsServer.stop())
            }
            let response: EventLoopFuture<Output> = client.execute(operation: "test", path: "/", httpMethod: .POST, config: config, context: TestEnvironment.context)

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
            static var _payloadOptions: AWSShapePayloadOptions = [.allowStreaming, .raw]
            let payload: AWSPayload
            private enum CodingKeys: CodingKey {}
        }
        let data = createRandomBuffer(45, 9182, size: bufferSize)
        var byteBuffer = ByteBufferAllocator().buffer(capacity: data.count)
        byteBuffer.writeBytes(data)

        let payload = AWSPayload.stream(size: bufferSize) { eventLoop in
            let size = min(blockSize, byteBuffer.readableBytes)
            // don't ask for 0 bytes
            XCTAssertNotEqual(size, 0)
            let buffer = byteBuffer.readSlice(length: size)!
            return eventLoop.makeSucceededFuture(.byteBuffer(buffer))
        }
        let input = Input(payload: payload)
        let response = client.execute(operation: "test", path: "/", httpMethod: .POST, input: input, config: config, context: TestEnvironment.context)

        try server.processRaw { request in
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
        XCTAssertNoThrow(try self.testRequestStreaming(config: config, client: client, server: awsServer, bufferSize: 81 * 1024, blockSize: 16 * 1024))
        XCTAssertNoThrow(try self.testRequestStreaming(config: config, client: client, server: awsServer, bufferSize: 128 * 1024, blockSize: S3ChunkedStreamReader.bufferSize))
        XCTAssertNoThrow(try self.testRequestStreaming(config: config, client: client, server: awsServer, bufferSize: 130 * 1024, blockSize: S3ChunkedStreamReader.bufferSize))
        XCTAssertNoThrow(try self.testRequestStreaming(config: config, client: client, server: awsServer, bufferSize: 128 * 1024, blockSize: 17 * 1024))
        XCTAssertNoThrow(try self.testRequestStreaming(config: config, client: client, server: awsServer, bufferSize: 18 * 1024, blockSize: 47 * 1024))
    }

    func testRequestStreamingTooMuchData() {
        struct Input: AWSEncodableShape & AWSShapeWithPayload {
            static var _payloadPath: String = "payload"
            static var _payloadOptions: AWSShapePayloadOptions = [.allowStreaming]
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
        do {
            // set up stream of 8 bytes but supply more than that
            let payload = AWSPayload.stream(size: 8) { eventLoop in
                var buffer = ByteBufferAllocator().buffer(capacity: 0)
                buffer.writeString("String longer than 8 bytes")
                return eventLoop.makeSucceededFuture(.byteBuffer(buffer))
            }
            let input = Input(payload: payload)
            let response = client.execute(operation: "test", path: "/", httpMethod: .POST, input: input, config: config, context: TestEnvironment.context)
            try response.wait()
        } catch let error as HTTPClientError where error == .bodyLengthMismatch {
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testRequestStreamingFile() {
        struct Input: AWSEncodableShape & AWSShapeWithPayload {
            static var _payloadPath: String = "payload"
            static var _payloadOptions: AWSShapePayloadOptions = [.allowStreaming]
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
            let response = client.execute(operation: "test", path: "/", httpMethod: .POST, input: input, config: config, context: TestEnvironment.context)

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
            static var _payloadOptions: AWSShapePayloadOptions = [.allowStreaming, .allowChunkedStreaming, .raw]
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
            let response = client.execute(operation: "test", path: "/", httpMethod: .POST, input: input, config: config, context: TestEnvironment.context)

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
            let response = client.execute(operation: "test", path: "/", httpMethod: .POST, config: config, context: TestEnvironment.context)

            try awsServer.processRaw { _ in
                let response = AWSTestServer.Response(httpStatus: .temporaryRedirect, headers: ["Location": awsServer.address], body: nil)
                return .result(response)
            }

            try response.wait()
            XCTFail("Shouldn't get here as the provided client doesn't follow redirects")
        } catch let error as AWSError {
            XCTAssertEqual(error.message, "Unhandled Error")
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testRegionEnum() {
        let region = Region(rawValue: "my-region")
        if Region.other("my-region") == region {
            XCTAssertEqual(region.rawValue, "my-region")
        } else {
            XCTFail("Did not construct Region.other()")
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
            let response = client.execute(operation: "test", path: "/", httpMethod: .POST, config: config, context: TestEnvironment.context)

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
                config: config,
                context: TestEnvironment.context
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
        class TestRetryPolicy: RetryPolicy {
            static let maxRetries: Int = 3
            var attempt: Int

            init() {
                self.attempt = 0
            }

            func getRetryWaitTime(error: Error, attempt: Int) -> RetryStatus? {
                self.attempt = attempt
                if attempt < Self.maxRetries { return .retry(wait: .milliseconds(100)) }
                return .dontRetry
            }
        }
        let retryPolicy = TestRetryPolicy()
        do {
            let awsServer = AWSTestServer(serviceProtocol: .json)
            let serverAddress = awsServer.address
            XCTAssertNoThrow(try awsServer.stop())
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

            try response.wait()
        } catch is NIOConnectionError {
            XCTAssertEqual(retryPolicy.attempt, TestRetryPolicy.maxRetries)
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
                config: config,
                context: TestEnvironment.context
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
                config: config,
                context: TestEnvironment.context.delegating(to: eventLoop)
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
            static let _encoding = [AWSMemberEncoding(label: "test", location: .header(locationName: "test"))]
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
                input: Input(),
                config: config,
                context: TestEnvironment.context
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
            static let _encoding = [AWSMemberEncoding(label: "test", location: .header(locationName: "test"))]
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
        let lock = Lock()
        let response: EventLoopFuture<Output> = client.execute(
            operation: "test",
            path: "/",
            httpMethod: .GET,
            input: Input(),
            config: config,
            context: TestEnvironment.context
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

    func testMiddlewareAppliedOnce() {
        struct URLAppendMiddleware: AWSServiceMiddleware {
            func chain(request: AWSRequest) throws -> AWSRequest {
                var request = request
                request.url.appendPathComponent("test")
                return request
            }
        }

        let awsServer = AWSTestServer(serviceProtocol: .json)
        let config = createServiceConfig(endpoint: awsServer.address)
        let client = createAWSClient(credentialProvider: .empty, middlewares: [URLAppendMiddleware()])
        defer {
            XCTAssertNoThrow(try client.syncShutdown())
            XCTAssertNoThrow(try awsServer.stop())
        }

        let response = client.execute(operation: "test", path: "/", httpMethod: .POST, config: config, context: TestEnvironment.context)

        XCTAssertNoThrow(try awsServer.processRaw { request in
            XCTAssertEqual(request.uri, "/test")
            return .result(AWSTestServer.Response.ok)
        })

        XCTAssertNoThrow(try response.wait())
    }
}
