//===----------------------------------------------------------------------===//
//
// This source file is part of the Soto for AWS open source project
//
// Copyright (c) 2017-2021 the Soto project authors
// Licensed under Apache License v2.0
//
// See LICENSE.txt for license information
// See CONTRIBUTORS.txt for the list of Soto project authors
//
// SPDX-License-Identifier: Apache-2.0
//
//===----------------------------------------------------------------------===//

#if compiler(>=5.5) && canImport(_Concurrency)

import AsyncHTTPClient
import Dispatch
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

@available(macOS 12.0, iOS 15.0, watchOS 8.0, tvOS 15.0, *)
class AWSClientAsyncTests: XCTestCase {
    func testGetCredential() {
        struct MyCredentialProvider: AsyncCredentialProvider {
            func getCredential(on eventLoop: EventLoop, logger: Logger) async throws -> Credential {
                return StaticCredential(accessKeyId: "key", secretAccessKey: "secret")
            }
        }
        let client = createAWSClient(credentialProvider: .custom { _ in MyCredentialProvider() })
        defer { XCTAssertNoThrow(try client.syncShutdown()) }
        XCTRunAsyncAndBlock {
            let credentialForSignature = try await client.getCredential(on: client.eventLoopGroup.next(), logger: TestEnvironment.logger)
            XCTAssertEqual(credentialForSignature.accessKeyId, "key")
            XCTAssertEqual(credentialForSignature.secretAccessKey, "secret")
        }
    }

    func testClientNoInputNoOutput() {
        let awsServer = AWSTestServer(serviceProtocol: .json)
        defer { XCTAssertNoThrow(try awsServer.stop()) }
        XCTRunAsyncAndBlock {
            let config = createServiceConfig(serviceProtocol: .json(version: "1.1"), endpoint: awsServer.address)
            let client = createAWSClient(credentialProvider: .empty, middlewares: [AWSLoggingMiddleware()])
            defer { XCTAssertNoThrow(try client.syncShutdown()) }

            async let asyncOutput: Void = client.execute(operation: "test", path: "/", httpMethod: .POST, serviceConfig: config, logger: TestEnvironment.logger)

            try awsServer.processRaw { _ in
                let response = AWSTestServer.Response(httpStatus: .ok, headers: [:], body: nil)
                return .result(response)
            }

            try await asyncOutput
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

        let awsServer = AWSTestServer(serviceProtocol: .json)
        defer { XCTAssertNoThrow(try awsServer.stop()) }
        XCTRunAsyncAndBlock {
            let config = createServiceConfig(serviceProtocol: .json(version: "1.1"), endpoint: awsServer.address)
            let client = createAWSClient(credentialProvider: .empty, middlewares: [AWSLoggingMiddleware()])
            defer { XCTAssertNoThrow(try client.syncShutdown()) }
            let input = Input(e: .second, i: [1, 2, 4, 8])

            async let asyncOutput: Void = client.execute(operation: "test", path: "/", httpMethod: .POST, serviceConfig: config, input: input, logger: TestEnvironment.logger)

            try awsServer.processRaw { request in
                let receivedInput = try JSONDecoder().decode(Input.self, from: request.body)
                XCTAssertEqual(receivedInput.e, .second)
                XCTAssertEqual(receivedInput.i, [1, 2, 4, 8])
                let response = AWSTestServer.Response(httpStatus: .ok, headers: [:], body: nil)
                return .result(response)
            }

            try await asyncOutput
        }
    }

    func testClientNoInputWithOutput() {
        struct Output: AWSDecodableShape & Encodable {
            let s: String
            let i: Int64
        }
        let awsServer = AWSTestServer(serviceProtocol: .json)
        defer { XCTAssertNoThrow(try awsServer.stop()) }
        XCTRunAsyncAndBlock {
            let eventLoopGroup = MultiThreadedEventLoopGroup(numberOfThreads: 1)
            defer { XCTAssertNoThrow(try eventLoopGroup.syncShutdownGracefully()) }
            let config = createServiceConfig(serviceProtocol: .json(version: "1.1"), endpoint: awsServer.address)
            let client = createAWSClient(
                credentialProvider: .empty,
                httpClientProvider: .createNewWithEventLoopGroup(eventLoopGroup)
            )
            defer { XCTAssertNoThrow(try client.syncShutdown()) }
            async let asyncOutput: Output = client.execute(operation: "test", path: "/", httpMethod: .POST, serviceConfig: config, logger: TestEnvironment.logger)

            try awsServer.processRaw { _ in
                let output = Output(s: "TestOutputString", i: 547)
                let byteBuffer = try JSONEncoder().encodeAsByteBuffer(output, allocator: ByteBufferAllocator())
                let response = AWSTestServer.Response(httpStatus: .ok, headers: [:], body: byteBuffer)
                return .result(response)
            }

            let output = try await asyncOutput
            XCTAssertEqual(output.s, "TestOutputString")
            XCTAssertEqual(output.i, 547)
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

        let stream = AsyncStream<ByteBuffer>() { cont in
            while byteBuffer.readableBytes > 0 {
                let size = min(blockSize, byteBuffer.readableBytes)
                let buffer = byteBuffer.readSlice(length: size)!
                cont.yield(buffer)
            }
            cont.finish()
        }
        let input = Input(payload: .asyncSequence(stream, size: bufferSize))
        XCTRunAsyncAndBlock {
            async let response: () = client.execute(
                operation: "test",
                path: "/",
                httpMethod: .POST,
                serviceConfig: config,
                input: input,
                logger: TestEnvironment.logger
            )

            try? server.processRaw { request in
                let bytes = request.body.getBytes(at: 0, length: request.body.readableBytes)
                XCTAssertEqual(bytes, data)
                let response = AWSTestServer.Response(httpStatus: .ok, headers: [:], body: nil)
                return .result(response)
            }

            _ = try await response
        }
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
}

#endif // compiler(>=5.5) && canImport(_Concurrency)
