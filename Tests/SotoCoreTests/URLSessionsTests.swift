//===----------------------------------------------------------------------===//
//
// This source file is part of the Soto for AWS open source project
//
// Copyright (c) 2023 the Soto project authors
// Licensed under Apache License v2.0
//
// See LICENSE.txt for license information
// See CONTRIBUTORS.txt for the list of Soto project authors
//
// SPDX-License-Identifier: Apache-2.0
//
//===----------------------------------------------------------------------===//

#if !os(Linux)

import Foundation
@_spi(SotoInternal) import SotoCore
import SotoTestUtils
import XCTest

class URLSessionTests: XCTestCase {
    func testClientNoInputNoOutput() async throws {
        do {
            let awsServer = AWSTestServer(serviceProtocol: .json)
            let config = createServiceConfig(serviceProtocol: .json(version: "1.1"), endpoint: awsServer.address)
            let client = createAWSClient(
                credentialProvider: .empty,
                middlewares: TestEnvironment.middlewares,
                httpClientProvider: .shared(URLSession.shared)
            )
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
            let client = createAWSClient(
                credentialProvider: .empty,
                middlewares: AWSLoggingMiddleware(),
                httpClientProvider: .shared(URLSession.shared)
            )
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
            let awsServer = AWSTestServer(serviceProtocol: .json)
            let config = createServiceConfig(serviceProtocol: .json(version: "1.1"), endpoint: awsServer.address)
            let client = createAWSClient(
                credentialProvider: .empty,
                httpClientProvider: .shared(URLSession.shared)
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
        struct Input: AWSEncodableShape {
            static var _options: AWSShapeOptions = [.allowStreaming]
            let payload: AWSHTTPBody
            func encode(to encoder: Encoder) throws {
                try self.payload.encode(to: encoder)
            }

            private enum CodingKeys: CodingKey {}
        }
        let data = createRandomBuffer(45, 9182, size: bufferSize)
        var byteBuffer = ByteBufferAllocator().buffer(capacity: data.count)
        byteBuffer.writeBytes(data)

        let payload = AWSHTTPBody(asyncSequence: byteBuffer.asyncSequence(chunkSize: blockSize), length: bufferSize)
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

    /* func testRequestStreaming() async throws {
         let awsServer = AWSTestServer(serviceProtocol: .json)
         let config = createServiceConfig(endpoint: awsServer.address)
         let client = createAWSClient(credentialProvider: .empty, httpClientProvider: .shared(URLSession.shared))
         defer {
             XCTAssertNoThrow(try awsServer.stop())
             XCTAssertNoThrow(try client.syncShutdown())
         }

         try await self.testRequestStreaming(config: config, client: client, server: awsServer, bufferSize: 128 * 1024, blockSize: 16 * 1024)
         try await self.testRequestStreaming(config: config, client: client, server: awsServer, bufferSize: 128 * 1024, blockSize: 17 * 1024)
         try await self.testRequestStreaming(config: config, client: client, server: awsServer, bufferSize: 18 * 1024, blockSize: 47 * 1024)
     } */

    func testStreamingResponse() async {
        struct Input: AWSEncodableShape {}
        struct Output: AWSDecodableShape {
            static let _options: AWSShapeOptions = .rawPayload
            let payload: AWSHTTPBody
            let test: String

            public init(from decoder: Decoder) throws {
                let response = decoder.userInfo[.awsResponse]! as! ResponseDecodingContainer
                let container = try decoder.singleValueContainer()
                self.payload = try container.decode(AWSHTTPBody.self)
                self.test = try response.decodeHeader(String.self, key: "test")
            }
        }
        let data = createRandomBuffer(45, 109, size: 128 * 1024)
        var sourceByteBuffer = ByteBufferAllocator().buffer(capacity: 128 * 1024)
        sourceByteBuffer.writeBytes(data)

        do {
            let awsServer = AWSTestServer(serviceProtocol: .json)
            let config = createServiceConfig(endpoint: awsServer.address)
            let client = createAWSClient(credentialProvider: .empty, httpClientProvider: .shared(URLSession.shared))
            defer {
                XCTAssertNoThrow(try client.syncShutdown())
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

#endif // !os(Linux)
