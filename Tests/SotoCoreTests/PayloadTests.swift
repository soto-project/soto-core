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

import Foundation
import HTTPTypes
import NIOCore
import NIOHTTP1
import SotoTestUtils
import Testing

@testable import SotoCore

struct PayloadTests {
    func testRequestPayload(_ payload: AWSHTTPBody, expectedResult: String) async throws {
        struct DataPayload: AWSEncodableShape {
            var _payload: AWSHTTPBody { self.data }
            let data: AWSHTTPBody
            func encode(to encoder: any Encoder) throws {
                try self.data.encode(to: encoder)
            }

            private enum CodingKeys: CodingKey {}
        }

        let mockHTTPClient = MockHTTPClient { request in
            let body = try await request.body.collect(upTo: .max)
            #expect(String(buffer: body) == expectedResult)
            return .init(response: .init(status: .ok))
        }
        let client = AWSClient(
            credentialProvider: .empty,
            httpClient: mockHTTPClient
        )
        try await withClient(client) {
            let config = createServiceConfig()
            let input = DataPayload(data: payload)
            _ = try await client.execute(
                operation: "test",
                path: "/",
                httpMethod: .post,
                serviceConfig: config,
                input: input,
                logger: TestEnvironment.logger
            )
        }
    }

    @Test func testDataRequestPayload() async throws {
        try await self.testRequestPayload(.init(bytes: Data("testDataPayload".utf8)), expectedResult: "testDataPayload")
    }

    @Test func testStringRequestPayload() async throws {
        try await self.testRequestPayload(.init(string: "testStringPayload"), expectedResult: "testStringPayload")
    }

    @Test func testByteBufferRequestPayload() async throws {
        var byteBuffer = ByteBufferAllocator().buffer(capacity: 32)
        byteBuffer.writeString("testByteBufferPayload")
        try await self.testRequestPayload(.init(buffer: byteBuffer), expectedResult: "testByteBufferPayload")
    }

    @Test func testResponsePayload() async throws {
        struct Output: AWSDecodableShape {
            static let _options: AWSShapeOptions = .rawPayload
            let payload: AWSHTTPBody

            init(from decoder: any Decoder) throws {
                let container = try decoder.singleValueContainer()
                self.payload = try container.decode(AWSHTTPBody.self)
            }
        }
        let mockHTTPClient = MockHTTPClient { request in
            let body = ByteBuffer(string: "testResponsePayload")
            return .init(response: .init(status: .ok), body: .init(buffer: body))
        }
        let client = AWSClient(
            credentialProvider: .empty,
            httpClient: mockHTTPClient
        )
        try await withClient(client) {
            let config = createServiceConfig()
            let output: Output = try await client.execute(
                operation: "test",
                path: "/",
                httpMethod: .post,
                serviceConfig: config,
                logger: TestEnvironment.logger
            )

            let responsePayload = try await String(buffer: output.payload.collect(upTo: .max))
            #expect(responsePayload == "testResponsePayload")
        }
    }
}
