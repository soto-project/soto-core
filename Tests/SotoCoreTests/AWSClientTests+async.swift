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
import Dispatch
import Logging
import NIOCore
import NIOFoundationCompat
import NIOHTTP1
import NIOPosix
@testable import SotoCore
import SotoTestUtils
import SotoXML
import XCTest

@available(macOS 10.15, iOS 13.0, tvOS 13.0, watchOS 6.0, *)
final class AWSClientAsyncTests: XCTestCase {
    func testGetCredential() async throws {
        struct MyCredentialProvider: AsyncCredentialProvider {
            func getCredential(on eventLoop: EventLoop, logger: Logger) async throws -> Credential {
                return StaticCredential(accessKeyId: "key", secretAccessKey: "secret")
            }
        }
        let client = createAWSClient(credentialProvider: .custom { _ in MyCredentialProvider() })
        defer { XCTAssertNoThrow(try client.syncShutdown()) }
        let credentialForSignature = try await client.getCredential(on: client.eventLoopGroup.next(), logger: TestEnvironment.logger)
        XCTAssertEqual(credentialForSignature.accessKeyId, "key")
        XCTAssertEqual(credentialForSignature.secretAccessKey, "secret")
    }

    func testClientNoInputNoOutput() async throws {
        #if os(iOS) // iOS async tests are failing in GitHub CI at the moment
        guard ProcessInfo.processInfo.environment["CI"] == nil else { return }
        #endif
        let awsServer = AWSTestServer(serviceProtocol: .json)
        defer { XCTAssertNoThrow(try awsServer.stop()) }
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

    func testClientWithInputNoOutput() async throws {
        #if os(iOS) // iOS async tests are failing in GitHub CI at the moment
        guard ProcessInfo.processInfo.environment["CI"] == nil else { return }
        #endif
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

    func testClientNoInputWithOutput() async throws {
        #if os(iOS) // iOS async tests are failing in GitHub CI at the moment
        guard ProcessInfo.processInfo.environment["CI"] == nil else { return }
        #endif
        struct Output: AWSDecodableShape & Encodable {
            let s: String
            let i: Int64
        }
        let awsServer = AWSTestServer(serviceProtocol: .json)
        defer { XCTAssertNoThrow(try awsServer.stop()) }

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

    func testRequestStreaming(config: AWSServiceConfig, client: AWSClient, server: AWSTestServer, bufferSize: Int, blockSize: Int) async throws {
        actor ByteBufferStream: AsyncSequence {
            typealias Element = ByteBuffer

            var byteBuffer: ByteBuffer
            let blockSize: Int

            init(byteBuffer: ByteBuffer, blockSize: Int) {
                self.byteBuffer = byteBuffer
                self.blockSize = blockSize
            }

            nonisolated func makeAsyncIterator() -> AsyncIterator {
                return AsyncIterator(stream: self)
            }

            func readSlice() -> ByteBuffer? {
                let size = Swift.min(self.byteBuffer.readableBytes, self.blockSize)
                if size > 0 {
                    return self.byteBuffer.readSlice(length: size)
                }
                return nil
            }

            struct AsyncIterator: AsyncIteratorProtocol {
                mutating func next() async throws -> ByteBuffer? {
                    return await self.stream.readSlice()
                }

                let stream: ByteBufferStream
            }
        }
        #if os(iOS) // iOS async tests are failing in GitHub CI at the moment
        guard ProcessInfo.processInfo.environment["CI"] == nil else { return }
        #endif
        struct Input: AWSEncodableShape & AWSShapeWithPayload {
            static var _payloadPath: String = "payload"
            static var _options: AWSShapeOptions = [.allowStreaming, .rawPayload]
            let payload: AWSPayload
            private enum CodingKeys: CodingKey {}
        }
        let data = createRandomBuffer(45, 9182, size: bufferSize)
        var byteBuffer = ByteBufferAllocator().buffer(capacity: data.count)
        byteBuffer.writeBytes(data)
        let stream = ByteBufferStream(byteBuffer: byteBuffer, blockSize: blockSize)
        let input = Input(payload: .asyncSequence(stream, size: bufferSize))

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

    func testRequestStreaming() async throws {
        #if os(iOS) // iOS async tests are failing in GitHub CI at the moment
        guard ProcessInfo.processInfo.environment["CI"] == nil else { return }
        #endif
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

    func testShutdown() async throws {
        let httpClient = HTTPClient(eventLoopGroupProvider: .createNew)

        let client = createAWSClient(httpClientProvider: .shared(httpClient))
        try await client.shutdown()
        let client2 = createAWSClient(httpClientProvider: .createNew)
        try await client2.shutdown()

        try await httpClient.shutdown()
    }
}
