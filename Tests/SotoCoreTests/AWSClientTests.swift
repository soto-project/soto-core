//===----------------------------------------------------------------------===//
//
// This source file is part of the Soto for AWS open source project
//
// Copyright (c) 2017-2026 the Soto project authors
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
import HTTPTypes
import Logging
import NIOConcurrencyHelpers
import NIOCore
import NIOFoundationEssentialsCompat
import NIOHTTP1
import NIOPosix
import SotoTestUtils
import Synchronization
import Testing

@testable @_spi(SotoInternal) import SotoCore

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif

class AWSClientTests {
    @Test func testGetCredential() async throws {
        let client = createAWSClient(credentialProvider: .static(accessKeyId: "key", secretAccessKey: "secret"))
        try await withClient(client) {
            let credentialForSignature = try await client.getCredential(logger: TestEnvironment.logger)
            #expect(credentialForSignature.accessKeyId == "key")
            #expect(credentialForSignature.secretAccessKey == "secret")
        }
    }

    @Test func testHeadersAreWritten() async throws {
        struct Input: AWSEncodableShape {
            let content: String
        }
        let client = AWSClient(
            credentialProvider: .static(accessKeyId: "foo", secretAccessKey: "bar"),
            httpClient: MockHTTPClient.httpBin
        )
        try await withClient(client) {
            let config = createServiceConfig(
                serviceProtocol: .json(version: "1.1")
            )
            let httpBinResponse: MockHTTPClient.HTTPBinResponse = try await client.execute(
                operation: "test",
                path: "/",
                httpMethod: .post,
                serviceConfig: config,
                input: Input(content: "test"),
                logger: TestEnvironment.logger
            )

            #expect(httpBinResponse.headers[.contentType] == "application/x-amz-json-1.1")
            #expect(httpBinResponse.headers[.xAmzDate] != nil)
            #expect(httpBinResponse.headers[.userAgent] == "Soto/8.0")
            #expect(httpBinResponse.headers[.authorization]?.hasPrefix("AWS4-HMAC-SHA256") == true)
        }
    }

    @Test func testSigV4aOptions() async throws {
        struct Input: AWSEncodableShape {
            let content: String
        }
        let client = createAWSClient(
            credentialProvider: .static(accessKeyId: "foo", secretAccessKey: "bar"),
            options: .init(signingAlgorithm: .sigV4a),
            httpClient: MockHTTPClient.httpBin
        )
        try await withClient(client) {
            let config = createServiceConfig(
                serviceProtocol: .json(version: "1.1")
            )
            let httpBinResponse: MockHTTPClient.HTTPBinResponse = try await client.execute(
                operation: "test",
                path: "/",
                httpMethod: .post,
                serviceConfig: config,
                input: Input(content: "test"),
                logger: TestEnvironment.logger
            )
            #expect(httpBinResponse.headers[.authorization]?.hasPrefix("AWS4-ECDSA-P256-SHA256") == true)
        }
    }

    @Test func testClientNoInputNoOutput() async throws {
        let config = createServiceConfig(serviceProtocol: .json(version: "1.1"))
        let client = createAWSClient(credentialProvider: .empty, middlewares: TestEnvironment.middlewares, httpClient: MockHTTPClient())
        try await withClient(client) {
            let _: Void = try await client.execute(
                operation: "test",
                path: "/",
                httpMethod: .post,
                serviceConfig: config,
                logger: TestEnvironment.logger
            )
        }
    }

    @Test func testClientWithInputNoOutput() async throws {
        enum InputEnum: String, Codable {
            case first
            case second
        }
        struct Input: AWSEncodableShape & Decodable {
            let e: InputEnum
            let i: [Int64]
        }

        let config = createServiceConfig(serviceProtocol: .json(version: "1.1"))
        let mockHTTPClient = MockHTTPClient { request in
            let receivedInput = try await JSONDecoder().decode(Input.self, from: request.body.collect(upTo: .max))
            #expect(receivedInput.e == .second)
            #expect(receivedInput.i == [1, 2, 4, 8])
            return .init(response: .init(status: .ok))
        }
        let client = createAWSClient(credentialProvider: .empty, middlewares: TestEnvironment.middlewares, httpClient: mockHTTPClient)
        let input = Input(e: .second, i: [1, 2, 4, 8])
        try await withClient(client) {
            let _: Void = try await client.execute(
                operation: "test",
                path: "/",
                httpMethod: .post,
                serviceConfig: config,
                input: input,
                logger: TestEnvironment.logger
            )
        }
    }

    @Test func testClientNoInputWithOutput() async throws {
        struct Output: AWSDecodableShape & Encodable {
            let s: String
            let i: Int64
        }
        let config = createServiceConfig(serviceProtocol: .json(version: "1.1"))
        let mockHTTPClient = MockHTTPClient { request in
            let output = Output(s: "TestOutputString", i: 547)
            let byteBuffer = try JSONEncoder().encodeAsByteBuffer(output, allocator: ByteBufferAllocator())
            return .init(response: .init(status: .ok), body: .init(buffer: byteBuffer))
        }
        let client = createAWSClient(
            credentialProvider: .empty,
            httpClient: mockHTTPClient
        )
        try await withClient(client) {
            let output: Output = try await client.execute(
                operation: "test",
                path: "/",
                httpMethod: .post,
                serviceConfig: config,
                logger: TestEnvironment.logger
            )

            #expect(output.s == "TestOutputString")
            #expect(output.i == 547)
        }
    }

    @Test func testBase64Coding() async throws {
        struct Output: AWSDecodableShape & Encodable {
            let data: AWSBase64Data
        }
        struct Input: AWSEncodableShape & Decodable {
            let data: AWSBase64Data
        }
        let config = createServiceConfig(serviceProtocol: .json(version: "1.1"))
        let mockHTTPClient = MockHTTPClient { request in
            let receivedInput = try await JSONDecoder().decode(Input.self, from: request.body.collect(upTo: .max))
            let output = Output(data: receivedInput.data)
            let byteBuffer = try JSONEncoder().encodeAsByteBuffer(output, allocator: ByteBufferAllocator())
            return .init(response: .init(status: .ok), body: .init(buffer: byteBuffer))
        }
        let client = createAWSClient(credentialProvider: .empty, httpClient: mockHTTPClient)
        try await withClient(client) {
            let input = Input(data: .data(Data("Test base64 data".utf8)))
            let output: Output = try await client.execute(
                operation: "test",
                path: "/",
                httpMethod: .post,
                serviceConfig: config,
                input: input,
                logger: TestEnvironment.logger
            )

            #expect(output.data.decoded() == [UInt8]("Test base64 data".utf8))
        }
    }

    func testRequestStreaming(bufferSize: Int, blockSize: Int, serviceConfig: AWSServiceConfig = createServiceConfig()) async throws {
        struct Input: AWSEncodableShape {
            static var _options: AWSShapeOptions { [.allowStreaming] }
            let payload: AWSHTTPBody
            func encode(to encoder: any Encoder) throws {
                try self.payload.encode(to: encoder)
            }

            private enum CodingKeys: CodingKey {}
        }
        let data = createRandomBuffer(45, 9182, size: bufferSize)
        let byteBuffer = ByteBuffer(bytes: data)

        let mockHTTPClient = MockHTTPClient { request in
            let bytes = try await request.body.collect(upTo: .max)
            #expect(bytes == byteBuffer)
            return .init(response: .init(status: .ok))
        }

        // TODO: Re-enable credentials once we have chunked upload testing in the mock client
        let client = createAWSClient(
            credentialProvider: .static(accessKeyId: "key", secretAccessKey: "secret"),
            httpClient: mockHTTPClient
        )
        try await withClient(client) {
            let payload = AWSHTTPBody(asyncSequence: byteBuffer.asyncSequence(chunkSize: blockSize), length: bufferSize)
            let input = Input(payload: payload)
            let _: Void = try await client.execute(
                operation: "test",
                path: "/",
                httpMethod: .post,
                serviceConfig: serviceConfig,
                input: input,
                logger: TestEnvironment.logger
            )
        }
    }

    @Test func testRequestStreaming() async throws {
        try await self.testRequestStreaming(bufferSize: 128 * 1024, blockSize: 16 * 1024)
        try await self.testRequestStreaming(bufferSize: 128 * 1024, blockSize: 17 * 1024)
        try await self.testRequestStreaming(bufferSize: 18 * 1024, blockSize: 47 * 1024)
    }

    @Test func testRequestS3Streaming() async throws {
        try await self.testRequestStreaming(bufferSize: 128 * 1024, blockSize: 16 * 1024, serviceConfig: createServiceConfig(service: "s3"))
        try await self.testRequestStreaming(bufferSize: 192 * 1024, blockSize: 128 * 1024, serviceConfig: createServiceConfig(service: "s3"))
        try await self.testRequestStreaming(bufferSize: 81 * 1024, blockSize: 16 * 1024, serviceConfig: createServiceConfig(service: "s3"))
        try await self.testRequestStreaming(bufferSize: 128 * 1024, blockSize: 64 * 1024, serviceConfig: createServiceConfig(service: "s3"))
        try await self.testRequestStreaming(bufferSize: 130 * 1024, blockSize: 64 * 1024, serviceConfig: createServiceConfig(service: "s3"))
        try await self.testRequestStreaming(bufferSize: 128 * 1024, blockSize: 17 * 1024, serviceConfig: createServiceConfig(service: "s3"))
        try await self.testRequestStreaming(bufferSize: 68 * 1024, blockSize: 67 * 1024, serviceConfig: createServiceConfig(service: "s3"))
        try await self.testRequestStreaming(bufferSize: 65537, blockSize: 65537, serviceConfig: createServiceConfig(service: "s3"))
        try await self.testRequestStreaming(bufferSize: 65552, blockSize: 65552, serviceConfig: createServiceConfig(service: "s3"))
    }

    @Test func testRequestChunkedStreaming() async throws {
        struct Input: AWSEncodableShape {
            static let _options: AWSShapeOptions = [.allowStreaming, .allowChunkedStreaming, .rawPayload]
            let payload: AWSHTTPBody
            func encode(to encoder: any Encoder) throws {
                try self.payload.encode(to: encoder)
            }
        }

        // supply buffer in 16k blocks
        let bufferSize = 145 * 1024
        let blockSize = 16 * 1024
        let data = createRandomBuffer(45, 9182, size: bufferSize)
        let byteBuffer = ByteBuffer(bytes: data)

        let mockHTTPClient = MockHTTPClient { request in
            let requestBody = try await request.body.collect(upTo: .max)
            #expect(requestBody == byteBuffer)
            return .init(response: .init(status: .ok))
        }
        let client = createAWSClient(credentialProvider: .empty, httpClient: mockHTTPClient)
        let config = createServiceConfig()
        try await withClient(client) {
            let payload = AWSHTTPBody(asyncSequence: byteBuffer.asyncSequence(chunkSize: blockSize), length: nil)
            let input = Input(payload: payload)
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

    @Test func testServerError() async throws {
        let count = Atomic(0)
        let mockHTTPClient = MockHTTPClient { request in
            if count.add(1, ordering: .relaxed).newValue < 5 {
                return MockHTTPClient.AWSError(status: .internalServerError, code: "InternalFailure").response(for: .restjson)
            } else {
                return .init(response: .init(status: .ok))
            }
        }
        let client = createAWSClient(credentialProvider: .empty, retryPolicy: .exponential(base: .milliseconds(200)), httpClient: mockHTTPClient)
        let config = createServiceConfig()
        do {
            try await withClient(client) {
                let _: Void = try await client.execute(
                    operation: "test",
                    path: "/",
                    httpMethod: .post,
                    serviceConfig: config,
                    logger: TestEnvironment.logger
                )
            }
        } catch let error as AWSServerError where error == .internalFailure {
        }
    }

    @Test func testClientRetry() async throws {
        struct Output: AWSDecodableShape, Encodable {
            let s: String
        }
        let count = Atomic(0)
        let mockHTTPClient = MockHTTPClient { request in
            if count.add(1, ordering: .relaxed).newValue < 3 {
                return MockHTTPClient.AWSError(status: .notImplemented, code: "NotImplemented").response(for: .json(version: "1.1"))
            } else {
                let output = Output(s: "TestOutputString")
                let byteBuffer = try JSONEncoder().encodeAsByteBuffer(output, allocator: ByteBufferAllocator())
                return .init(response: .init(status: .ok), body: .init(buffer: byteBuffer))
            }
        }
        let client = createAWSClient(credentialProvider: .empty, retryPolicy: .jitter(), httpClient: mockHTTPClient)
        let config = createServiceConfig(serviceProtocol: .json(version: "1.1"))
        try await withClient(client) {
            let output: Output = try await client.execute(
                operation: "test",
                path: "/",
                httpMethod: .post,
                serviceConfig: config,
                logger: TestEnvironment.logger
            )
            #expect(output.s == "TestOutputString")
        }
    }

    @Test func testCustomRetryPolicy() async throws {
        final class TestRetryPolicy: RetryPolicy {
            static let maxRetries: Int = 3
            let attempt = Atomic(0)

            init() {}

            func getRetryWaitTime(error: any Error, attempt: Int) -> RetryStatus? {
                self.attempt.store(attempt, ordering: .relaxed)
                if attempt < Self.maxRetries { return .retry(wait: .milliseconds(100)) }
                return .dontRetry
            }
        }
        let retryPolicy = TestRetryPolicy()
        let mockHTTPClient = MockHTTPClient { request in
            MockHTTPClient.AWSError(status: .serviceUnavailable, code: "ServiceUnavailable").response(for: .json(version: "1.1"))
        }
        let client = createAWSClient(credentialProvider: .empty, retryPolicy: retryPolicy, httpClient: mockHTTPClient)
        let config = createServiceConfig(serviceProtocol: .json(version: "1.1"))
        try await withClient(client) {
            do {
                let _: Void = try await client.execute(
                    operation: "test",
                    path: "/",
                    httpMethod: .post,
                    serviceConfig: config,
                    logger: TestEnvironment.logger
                )
            } catch let error as AWSServerError where error == .serviceUnavailable {
                #expect(retryPolicy.attempt.load(ordering: .relaxed) == TestRetryPolicy.maxRetries)
            }
        }
    }

    @Test func testClientRetryFail() async throws {
        let mockHTTPClient = MockHTTPClient { request in
            MockHTTPClient.AWSError(status: .serviceUnavailable, code: "ServiceUnavailable").response(for: .json(version: "1.1"))
        }
        let client = createAWSClient(credentialProvider: .empty, retryPolicy: .jitter(base: .milliseconds(50)), httpClient: mockHTTPClient)
        let config = createServiceConfig(serviceProtocol: .json(version: "1.1"))
        try await withClient(client) {
            do {
                let _: Void = try await client.execute(
                    operation: "test",
                    path: "/",
                    httpMethod: .post,
                    serviceConfig: config,
                    logger: TestEnvironment.logger
                )
            } catch let error as AWSServerError where error == .serviceUnavailable {
            }
        }
    }

    @Test func testStreamingResponse() async throws {
        struct Input: AWSEncodableShape {}
        struct Output: AWSDecodableShape {
            static let _options: AWSShapeOptions = .rawPayload
            let payload: AWSHTTPBody
            let test: String

            public init(from decoder: any Decoder) throws {
                let response = decoder.userInfo[.awsResponse]! as! ResponseDecodingContainer
                let container = try decoder.singleValueContainer()
                self.payload = try container.decode(AWSHTTPBody.self)
                self.test = try response.decodeHeader(String.self, key: "test")
            }
        }
        let data = createRandomBuffer(45, 109, size: 128 * 1024)
        let sourceByteBuffer = ByteBuffer(bytes: data)

        let mockHTTPClient = MockHTTPClient { request in
            .init(
                response: .init(status: .ok, headerFields: [HTTPField.Name("test")!: "TestHeader"]),
                body: .init(asyncSequence: sourceByteBuffer.asyncSequence(chunkSize: 15000), length: nil)
            )
        }
        let client = createAWSClient(credentialProvider: .empty, httpClient: mockHTTPClient)
        let config = createServiceConfig(serviceProtocol: .json(version: "1.1"))
        try await withClient(client) {
            let output: Output = try await client.execute(
                operation: "test",
                path: "/",
                httpMethod: .get,
                serviceConfig: config,
                input: Input(),
                logger: TestEnvironment.logger
            )

            let responseBuffer = try await output.payload.collect(upTo: .max)
            #expect(responseBuffer == sourceByteBuffer)
            #expect(output.test == "TestHeader")
        }
    }

    @Suite(.serialized)
    struct Serialized {
        /// Given this function is being used to test AHC responses it should continue to use AWSTestServer
        func testRequestStreamingWithPayload(_ payload: AWSHTTPBody) async throws {
            struct Input: AWSEncodableShape {
                static var _options: AWSShapeOptions { [.allowStreaming] }
                let payload: AWSHTTPBody
                func encode(to encoder: any Encoder) throws {
                    try self.payload.encode(to: encoder)
                }

                private enum CodingKeys: CodingKey {}
            }

            let awsServer = AWSTestServer(serviceProtocol: .json)
            let config = createServiceConfig(endpoint: awsServer.address)
            let client = createAWSClient(credentialProvider: .empty)
            try await withTeardown {
                let input = Input(payload: payload)
                async let responseTask: Void = client.execute(
                    operation: "test",
                    path: "/",
                    httpMethod: .post,
                    serviceConfig: config,
                    input: input,
                    logger: TestEnvironment.logger
                )
                try await responseTask
            } teardown: {
                try? awsServer.stop()
                try? await client.shutdown()
            }
        }

        @Test func testRequestStreamingTooMuchData() async throws {
            // set up stream of 8 bytes but supply more than that
            let buffer = ByteBuffer(string: "String longer than 8 bytes")
            let payload = AWSHTTPBody(asyncSequence: buffer.asyncSequence(chunkSize: 1024), length: buffer.readableBytes - 1)
            let error = await #expect(throws: AWSClient.ClientError.self) {
                try await self.testRequestStreamingWithPayload(payload)
            }
            #expect(error == .bodyLengthMismatch)

        }

        @Test func testRequestStreamingNotEnoughData() async throws {
            // set up stream of 8 bytes but supply more than that
            let buffer = ByteBuffer(string: "String longer than 8 bytes")
            let payload = AWSHTTPBody(asyncSequence: buffer.asyncSequence(chunkSize: 1024), length: buffer.readableBytes + 1)
            let error = await #expect(throws: AWSClient.ClientError.self) {
                try await self.testRequestStreamingWithPayload(payload)
            }
            #expect(error == .bodyLengthMismatch)
        }
    }
}

#if ServiceLifecycleSupport

import ServiceLifecycle

extension AWSClientTests {
    @Test func testServiceLifecycle() async throws {
        var logger = Logger(label: "AWSClient")
        logger.logLevel = .debug
        let awsClient = createAWSClient(credentialProvider: .empty, httpClient: HTTPClient.shared, logger: logger)
        let serviceGroup = ServiceGroup(services: [awsClient], logger: logger)
        try await withThrowingTaskGroup(of: Void.self) { group in
            group.addTask {
                try await serviceGroup.run()
            }
            try await Task.sleep(for: .milliseconds(100))
            await serviceGroup.triggerGracefulShutdown()
        }
    }
}
#endif  // ServiceLifecycleSupport
