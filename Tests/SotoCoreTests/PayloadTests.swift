//===----------------------------------------------------------------------===//
//
// This source file is part of the Soto for AWS open source project
//
// Copyright (c) 2017-2020 the Soto project authors
// Licensed under Apache License v2.0
//
// See LICENSE.txt for license information
// See CONTRIBUTORS.txt for the list of Soto project authors
//
// SPDX-License-Identifier: Apache-2.0
//
//===----------------------------------------------------------------------===//

import NIOCore
import SotoTestUtils
import XCTest

@testable import SotoCore

class PayloadTests: XCTestCase {
    func testRequestPayload(_ payload: AWSHTTPBody, expectedResult: String) async throws {
        struct DataPayload: AWSEncodableShape {
            var _payload: AWSHTTPBody { self.data }
            let data: AWSHTTPBody
            func encode(to encoder: Encoder) throws {
                try self.data.encode(to: encoder)
            }

            private enum CodingKeys: CodingKey {}
        }

        let client: AWSClient
        do {
            let awsServer = AWSTestServer(serviceProtocol: .json)
            let config = createServiceConfig(endpoint: awsServer.address)
            client = createAWSClient(credentialProvider: .empty)
            let input = DataPayload(data: payload)
            async let responseTask: Void = client.execute(
                operation: "test",
                path: "/",
                httpMethod: .POST,
                serviceConfig: config,
                input: input,
                logger: TestEnvironment.logger
            )

            try awsServer.processRaw { request in
                XCTAssertEqual(request.body.getString(at: 0, length: request.body.readableBytes), expectedResult)
                return .result(.ok)
            }

            try await responseTask
            try awsServer.stop()
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
        try await client.shutdown()
    }

    func testDataRequestPayload() async throws {
        try await self.testRequestPayload(.init(bytes: Data("testDataPayload".utf8)), expectedResult: "testDataPayload")
    }

    func testStringRequestPayload() async throws {
        try await self.testRequestPayload(.init(string: "testStringPayload"), expectedResult: "testStringPayload")
    }

    func testByteBufferRequestPayload() async throws {
        var byteBuffer = ByteBufferAllocator().buffer(capacity: 32)
        byteBuffer.writeString("testByteBufferPayload")
        try await self.testRequestPayload(.init(buffer: byteBuffer), expectedResult: "testByteBufferPayload")
    }

    func testResponsePayload() async throws {
        struct Output: AWSDecodableShape {
            static let _options: AWSShapeOptions = .rawPayload
            let payload: AWSHTTPBody

            init(from decoder: Decoder) throws {
                let container = try decoder.singleValueContainer()
                self.payload = try container.decode(AWSHTTPBody.self)
            }
        }
        let client: AWSClient
        do {
            let awsServer = AWSTestServer(serviceProtocol: .json)
            let config = createServiceConfig(endpoint: awsServer.address)
            client = createAWSClient(credentialProvider: .empty)
            async let responseTask: Output = client.execute(
                operation: "test",
                path: "/",
                httpMethod: .POST,
                serviceConfig: config,
                logger: TestEnvironment.logger
            )

            try awsServer.processRaw { _ in
                var byteBuffer = ByteBufferAllocator().buffer(capacity: 0)
                byteBuffer.writeString("testResponsePayload")
                let response = AWSTestServer.Response(httpStatus: .ok, headers: [:], body: byteBuffer)
                return .result(response)
            }

            let output = try await responseTask

            let responsePayload = try await String(buffer: output.payload.collect(upTo: .max))
            XCTAssertEqual(responsePayload, "testResponsePayload")
            // XCTAssertEqual(output.i, 547)
            try awsServer.stop()
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
        try await client.shutdown()
    }
}
