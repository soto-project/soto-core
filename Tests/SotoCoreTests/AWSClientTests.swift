//===----------------------------------------------------------------------===//
//
// This source file is part of the Soto for AWS open source project
//
// Copyright (c) 2017-2023 the Soto project authors
// Licensed under Apache License v2.0
//
// See LICENSE.txt for license information
// See CONTRIBUTORS.txt for the list of Soto project authors
//
// SPDX-License-Identifier: Apache-2.0
//
//===----------------------------------------------------------------------===//

import AsyncHTTPClient
import Atomics
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

class AWSClientTests: XCTestCase {
    func testGetCredential() async throws {
        let client = createAWSClient(credentialProvider: .static(accessKeyId: "key", secretAccessKey: "secret"))
        defer {
            XCTAssertNoThrow(try client.syncShutdown())
        }

        let credentialForSignature = try await client.getCredential(logger: TestEnvironment.logger)
        XCTAssertEqual(credentialForSignature.accessKeyId, "key")
        XCTAssertEqual(credentialForSignature.secretAccessKey, "secret")
    }

    // this test only really works on Linux as it requires the MetaDataService. On mac it will just pass automatically
    func testExpiredCredential() async throws {
        let client = createAWSClient(credentialProvider: .selector(.ec2, .ecs))
        defer {
            XCTAssertNoThrow(try client.syncShutdown())
        }

        do {
            _ = try await client.getCredential(logger: TestEnvironment.logger)
            XCTFail("Should not get here")
        } catch let error as CredentialProviderError where error == .noProvider {
            // credentials request should fail. One possible error is a connectTimerout
        } catch {
            XCTFail("Unexpected error \(error)")
        }
    }

    func testShutdown() async throws {
        let httpClient = HTTPClient(eventLoopGroupProvider: .createNew)
        defer { XCTAssertNoThrow(try httpClient.syncShutdown()) }

        let client = createAWSClient(httpClientProvider: .shared(httpClient))
        try await client.shutdown()
    }

    func testShutdownWithEventLoop() async throws {
        let eventLoopGroup = MultiThreadedEventLoopGroup(numberOfThreads: 1)
        defer { XCTAssertNoThrow(try eventLoopGroup.syncShutdownGracefully()) }

        let client = createAWSClient(httpClientProvider: .createNewWithEventLoopGroup(eventLoopGroup))
        try await client.shutdown()
    }

    func testHeadersAreWritten() async throws {
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
        async let responseTask: AWSTestServer.HTTPBinResponse = client.execute(
            operation: "test",
            path: "/",
            httpMethod: .POST,
            serviceConfig: config,
            input: Input(content: "test"),
            logger: TestEnvironment.logger
        )

        XCTAssertNoThrow(try awsServer.httpBin())

        let httpBinResponse = try await responseTask
        let httpHeaders = HTTPHeaders(httpBinResponse.headers.map { ($0, $1) })

        XCTAssertEqual(httpHeaders["content-length"].first, "18")
        XCTAssertEqual(httpHeaders["content-type"].first, "application/x-amz-json-1.1")
        XCTAssertNotNil(httpHeaders["authorization"].first)
        XCTAssertNotNil(httpHeaders["x-amz-date"].first)
        XCTAssertEqual(httpHeaders["user-agent"].first, "Soto/6.0")
        XCTAssertEqual(httpHeaders["host"].first, "localhost:\(awsServer.serverPort)")
    }

    func testClientNoInputNoOutput() async throws {
        do {
            let awsServer = AWSTestServer(serviceProtocol: .json)
            let config = createServiceConfig(serviceProtocol: .json(version: "1.1"), endpoint: awsServer.address)
            let client = createAWSClient(credentialProvider: .empty, middlewares: [AWSLoggingMiddleware()])
            defer {
                XCTAssertNoThrow(try client.syncShutdown())
                XCTAssertNoThrow(try awsServer.stop())
            }
            async let responseTask: Void = client.execute(
                operation: "test",
                path: "/",
                httpMethod: .POST,
                serviceConfig: config,
                logger: TestEnvironment.logger
            )

            try awsServer.processRaw { _ in
                let response = AWSTestServer.Response(httpStatus: .ok, headers: [:], body: nil)
                return .result(response)
            }

            try await responseTask
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testClientWithInputNoOutput() async throws {
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
            async let responseTask: Void = client.execute(
                operation: "test",
                path: "/",
                httpMethod: .POST,
                serviceConfig: config,
                input: input,
                logger: TestEnvironment.logger
            )

            try awsServer.processRaw { request in
                let receivedInput = try JSONDecoder().decode(Input.self, from: request.body)
                XCTAssertEqual(receivedInput.e, .second)
                XCTAssertEqual(receivedInput.i, [1, 2, 4, 8])
                let response = AWSTestServer.Response(httpStatus: .ok, headers: [:], body: nil)
                return .result(response)
            }

            try await responseTask
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testClientNoInputWithOutput() async throws {
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
            async let response: Output = client.execute(
                operation: "test",
                path: "/",
                httpMethod: .POST,
                serviceConfig: config,
                logger: TestEnvironment.logger
            )

            try awsServer.processRaw { _ in
                let output = Output(s: "TestOutputString", i: 547)
                let byteBuffer = try JSONEncoder().encodeAsByteBuffer(output, allocator: ByteBufferAllocator())
                let response = AWSTestServer.Response(httpStatus: .ok, headers: [:], body: byteBuffer)
                return .result(response)
            }

            let output = try await response

            XCTAssertEqual(output.s, "TestOutputString")
            XCTAssertEqual(output.i, 547)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testRequestStreaming(config: AWSServiceConfig, client: AWSClient, server: AWSTestServer, bufferSize: Int, blockSize: Int) async throws {
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
        async let responseTask: Void = client.execute(operation: "test", path: "/", httpMethod: .POST, serviceConfig: config, input: input, logger: TestEnvironment.logger)

        try? server.processRaw { request in
            let bytes = request.body.getBytes(at: 0, length: request.body.readableBytes)
            XCTAssertEqual(bytes, data)
            let response = AWSTestServer.Response(httpStatus: .ok, headers: [:], body: nil)
            return .result(response)
        }

        try await responseTask
    }

    /*    func testRequestStreaming() async throws {
         let awsServer = AWSTestServer(serviceProtocol: .json)
         let httpClient = HTTPClient(eventLoopGroupProvider: .createNew)
         let config = createServiceConfig(endpoint: awsServer.address)
         let client = createAWSClient(credentialProvider: .empty, httpClientProvider: .shared(httpClient))
         defer {
             XCTAssertNoThrow(try awsServer.stop())
             XCTAssertNoThrow(try client.syncShutdown())
             XCTAssertNoThrow(try httpClient.syncShutdown())
         }

         try await self.testRequestStreaming(config: config, client: client, server: awsServer, bufferSize: 128 * 1024, blockSize: 16 * 1024)
         try await self.testRequestStreaming(config: config, client: client, server: awsServer, bufferSize: 128 * 1024, blockSize: 17 * 1024)
         try await self.testRequestStreaming(config: config, client: client, server: awsServer, bufferSize: 18 * 1024, blockSize: 47 * 1024)
     }

     func testRequestS3Streaming() async throws {
         let awsServer = AWSTestServer(serviceProtocol: .json)
         let httpClient = HTTPClient(eventLoopGroupProvider: .createNew)
         let config = createServiceConfig(service: "s3", endpoint: awsServer.address)
         let client = createAWSClient(credentialProvider: .static(accessKeyId: "foo", secretAccessKey: "bar"), httpClientProvider: .shared(httpClient))
         defer {
             XCTAssertNoThrow(try client.syncShutdown())
             XCTAssertNoThrow(try awsServer.stop())
             XCTAssertNoThrow(try httpClient.syncShutdown())
         }

         try await self.testRequestStreaming(config: config, client: client, server: awsServer, bufferSize: 128 * 1024, blockSize: 16 * 1024)
         try await self.testRequestStreaming(config: config, client: client, server: awsServer, bufferSize: 192 * 1024, blockSize: 128 * 1024)
         try await self.testRequestStreaming(config: config, client: client, server: awsServer, bufferSize: 81 * 1024, blockSize: 16 * 1024)
         try await self.testRequestStreaming(config: config, client: client, server: awsServer, bufferSize: 128 * 1024, blockSize: S3ChunkedStreamReader.bufferSize)
         try await self.testRequestStreaming(config: config, client: client, server: awsServer, bufferSize: 130 * 1024, blockSize: S3ChunkedStreamReader.bufferSize)
         try await self.testRequestStreaming(config: config, client: client, server: awsServer, bufferSize: 128 * 1024, blockSize: 17 * 1024)
         try await self.testRequestStreaming(config: config, client: client, server: awsServer, bufferSize: 68 * 1024, blockSize: 67 * 1024)
         try await self.testRequestStreaming(config: config, client: client, server: awsServer, bufferSize: 65537, blockSize: 65537)
         try await self.testRequestStreaming(config: config, client: client, server: awsServer, bufferSize: 65552, blockSize: 65552)
     }

     func testRequestStreamingAvoidStackOverflow() async throws {
         let awsServer = AWSTestServer(serviceProtocol: .json)
         let httpClient = HTTPClient(eventLoopGroupProvider: .createNew)
         let config = createServiceConfig(service: "s3", endpoint: awsServer.address)
         let client = createAWSClient(credentialProvider: .static(accessKeyId: "foo", secretAccessKey: "bar"), httpClientProvider: .shared(httpClient))
         defer {
             XCTAssertNoThrow(try client.syncShutdown())
             XCTAssertNoThrow(try awsServer.stop())
             XCTAssertNoThrow(try httpClient.syncShutdown())
         }

         try await self.testRequestStreaming(config: config, client: client, server: awsServer, bufferSize: 16 * 1024, blockSize: 8)
     }

     func testRequestStreamingWithPayload(_ payload: AWSPayload) async throws {
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
         async let responseTask: Void = client.execute(operation: "test", path: "/", httpMethod: .POST, serviceConfig: config, input: input, logger: TestEnvironment.logger)
         try await responseTask
     }

     func testRequestStreamingTooMuchData() async throws {
         // set up stream of 8 bytes but supply more than that
         let payload = AWSPayload.stream(size: 8) { eventLoop in
             var buffer = ByteBufferAllocator().buffer(capacity: 0)
             buffer.writeString("String longer than 8 bytes")
             return eventLoop.makeSucceededFuture(.byteBuffer(buffer))
         }
         do {
             try await self.testRequestStreamingWithPayload(payload)
             XCTFail("Should not get here")
         } catch {
             XCTAssertEqual(error as? AWSClient.ClientError, .tooMuchData)
         }
     }

     func testRequestStreamingNotEnoughData() async throws {
         var byteBuffer = ByteBufferAllocator().buffer(staticString: "Buffer")
         let payload = AWSPayload.stream(size: byteBuffer.readableBytes + 1) { eventLoop in
             let size = byteBuffer.readableBytes
             if size == 0 {
                 return eventLoop.makeSucceededFuture(.end)
             }
             let buffer = byteBuffer.readSlice(length: size)!
             return eventLoop.makeSucceededFuture(.byteBuffer(buffer))
         }
         do {
             try await self.testRequestStreamingWithPayload(payload)
             XCTFail("Should not get here")
         } catch {
             XCTAssertEqual(error as? AWSClient.ClientError, .notEnoughData)
         }
     }

     func testRequestStreamingFile() async throws {
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
             let fileHandle = try await fileIO.openFile(path: filename, mode: .read, eventLoop: httpClient.eventLoopGroup.next()).get()
             defer {
                 XCTAssertNoThrow(try fileHandle.close())
                 XCTAssertNoThrow(try threadPool.syncShutdownGracefully())
             }

             let input = Input(payload: .fileHandle(fileHandle, size: bufferSize, fileIO: fileIO) { size in print(size) })
             async let responseTask: Void = client.execute(operation: "test", path: "/", httpMethod: .POST, serviceConfig: config, input: input, logger: TestEnvironment.logger)

             try awsServer.processRaw { request in
                 XCTAssertNil(request.headers["transfer-encoding"])
                 XCTAssertEqual(request.headers["Content-Length"], bufferSize.description)
                 let requestData = request.body.getData(at: 0, length: request.body.readableBytes)
                 XCTAssertEqual(requestData, data)
                 let response = AWSTestServer.Response(httpStatus: .ok, headers: [:], body: nil)
                 return .result(response)
             }

             try await responseTask
         } catch let error as AWSClient.ClientError where error == .tooMuchData {
         } catch {
             XCTFail("Unexpected error: \(error)")
         }
     }

     func testRequestChunkedStreaming() async throws {
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
             async let responseTask: Void = client.execute(operation: "test", path: "/", httpMethod: .POST, serviceConfig: config, input: input, logger: TestEnvironment.logger)

             try awsServer.processRaw { request in
                 let bytes = request.body.getBytes(at: 0, length: request.body.readableBytes)
                 XCTAssertTrue(bytes == data)
                 let response = AWSTestServer.Response(httpStatus: .ok, headers: [:], body: nil)
                 return .result(response)
             }

             try await responseTask
         } catch {
             XCTFail("Unexpected error: \(error)")
         }
     }*/

    func testProvideHTTPClient() async {
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
            async let responseTask: Void = client.execute(operation: "test", path: "/", httpMethod: .POST, serviceConfig: config, logger: TestEnvironment.logger)

            try awsServer.processRaw { _ in
                let response = AWSTestServer.Response(httpStatus: .temporaryRedirect, headers: ["Location": awsServer.address], body: nil)
                return .result(response)
            }

            try await responseTask
            XCTFail("Shouldn't get here as the provided client doesn't follow redirects")
        } catch let error as AWSRawError {
            XCTAssertEqual(error.context.message, "Unhandled Error")
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testServerError() async {
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
            async let responseTask: Void = client.execute(operation: "test", path: "/", httpMethod: .POST, serviceConfig: config, logger: TestEnvironment.logger)

            var count = 0
            try awsServer.processRaw { _ in
                count += 1
                if count < 5 {
                    return .error(.internal, continueProcessing: true)
                } else {
                    return .result(.ok)
                }
            }

            try await responseTask
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

    func testClientRetry() async throws {
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
            async let responseTask: Output = client.execute(
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

            let output = try await responseTask

            XCTAssertEqual(output.s, "TestOutputString")
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testCustomRetryPolicy() async {
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
            async let responseTask: Void = client.execute(
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

            try await responseTask
        } catch let error as AWSServerError where error == .serviceUnavailable {
            XCTAssertEqual(retryPolicy.attempt.load(ordering: .relaxed), TestRetryPolicy.maxRetries)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testClientRetryFail() async {
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
            async let responseTask: Output = client.execute(
                operation: "test",
                path: "/",
                httpMethod: .POST,
                serviceConfig: config,
                logger: TestEnvironment.logger
            )

            try awsServer.processRaw { _ in
                return .error(.accessDenied, continueProcessing: false)
            }

            let output = try await responseTask

            XCTAssertEqual(output.s, "TestOutputString")
        } catch let error as AWSClientError where error == AWSClientError.accessDenied {
            XCTAssertEqual(error.message, AWSTestServer.ErrorType.accessDenied.message)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    /// verify we are not calling the Retry handler when streaming a request
    func testDontRetryStreamingRequests() async {
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
            async let responseTask: Void = client.execute(
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

            try await responseTask
        } catch let error as AWSClientError where error == .accessDenied {
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testClientResponseEventLoop() async {
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
            async let responseTask: Void = client.execute(
                operation: "test",
                path: "/",
                httpMethod: .POST,
                serviceConfig: config,
                logger: TestEnvironment.logger
            )

            try awsServer.processRaw { _ in
                return .result(.ok)
            }

            try await responseTask
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testStreamingResponse() async {
        struct Input: AWSEncodableShape {}
        struct Output: AWSDecodableShape & AWSShapeWithPayload {
            static let _encoding = [AWSMemberEncoding(label: "test", location: .header("test"))]
            static let _payloadPath: String = "payload"
            static let _options: AWSShapeOptions = .rawPayload
            let payload: HTTPBody
            let test: String
        }
        let data = createRandomBuffer(45, 109, size: 128 * 1024)
        var sourceByteBuffer = ByteBufferAllocator().buffer(capacity: 128 * 1024)
        sourceByteBuffer.writeBytes(data)

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
            async let responseTask: Output = client.execute(
                operation: "test",
                path: "/",
                httpMethod: .GET,
                serviceConfig: config,
                input: Input(),
                logger: TestEnvironment.logger
            )

            try awsServer.processRaw { _ in
                var byteBuffer = ByteBufferAllocator().buffer(capacity: 128 * 1024)
                byteBuffer.writeBytes(data)
                let response = AWSTestServer.Response(httpStatus: .ok, headers: ["test": "TestHeader"], body: byteBuffer)
                return .result(response)
            }

            let result = try await responseTask
            let responseBuffer = try await result.payload.collect(upTo: .max)
            XCTAssertEqual(responseBuffer, sourceByteBuffer)
            XCTAssertEqual(result.test, "TestHeader")
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }
}
