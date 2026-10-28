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

import Foundation
import HTTPTypes
import NIOCore
import SotoTestUtils
import Testing

@testable import SotoCore

class MiddlewareTests {
    struct CatchRequestError: Error {
        let request: AWSHTTPRequest
        let context: AWSMiddlewareContext
    }

    func testMiddleware(
        _ middleware: some AWSMiddlewareProtocol,
        serviceName: String = "service",
        serviceOptions: AWSServiceConfig.Options = [],
        uri: String = "/",
        test: @escaping @Sendable (AWSHTTPRequest) -> Void
    ) async throws {
        try await testServiceConfig(
            createServiceConfig(
                region: .useast1,
                service: serviceName,
                middlewares: middleware,
                options: serviceOptions
            ),
            uri: uri,
            test: test
        )
    }

    func testServiceConfig(
        _ serviceConfig: AWSServiceConfig,
        uri: String = "/",
        test: @escaping @Sendable (AWSHTTPRequest) -> Void
    ) async throws {
        let mockHTTPClient = MockAWSHTTPClient { request in
            test(request)
            return .init(response: .init(status: .ok))
        }
        let client = AWSClient(
            credentialProvider: .empty,
            httpClient: mockHTTPClient
        )
        defer { #expect(throws: Never.self) { try client.syncShutdown() } }

        _ = try await client.execute(operation: "test", path: uri, httpMethod: .post, serviceConfig: serviceConfig, logger: TestEnvironment.logger)
    }

    @Test func testMiddlewareAppliedOnce() async throws {
        struct URLAppendMiddleware: AWSMiddlewareProtocol {
            func handle(
                _ request: AWSHTTPRequest,
                context: AWSMiddlewareContext,
                next: (AWSHTTPRequest, AWSMiddlewareContext) async throws -> AWSHTTPResponse
            ) async throws -> AWSHTTPResponse {
                var request = request
                request.request.url?.appendPathComponent("it")
                return try await next(request, context)
            }
        }
        try await self.testMiddleware(URLAppendMiddleware(), uri: "/test") { request in
            #expect(request.request.path == "/test/it")
        }
    }

    @Test func testEditHeaderMiddlewareAddHeader() async throws {
        let testAdd = HTTPField.Name("testAdd")!
        // Test add header
        let middleware = AWSEditHeadersMiddleware(
            .add(name: testAdd, value: "testValue"),
            .add(name: .userAgent, value: "testEditHeaderMiddleware")
        )
        try await self.testMiddleware(middleware) { request in
            #expect(request.headers[testAdd] == "testValue")
            #expect(request.headers[.userAgent] == "Soto/8.0, testEditHeaderMiddleware")
        }
    }

    @Test func testEditHeaderMiddlewareReplaceHeader() async throws {
        // Test replace header
        let middleware = AWSEditHeadersMiddleware(
            .replace(name: .userAgent, value: "testEditHeaderMiddleware")
        )
        try await self.testMiddleware(middleware) { request in
            #expect(request.headers[.userAgent] == "testEditHeaderMiddleware")
        }
    }

    @Test func testS3MiddlewareNoBucket() async throws {
        // Test virual address
        try await self.testMiddleware(S3Middleware(), uri: "/") { request in
            #expect(request.request.url?.absoluteString == "https://service.us-east-1.amazonaws.com/")
        }
    }

    @Test func testS3MiddlewareVirtualAddress() async throws {
        // Test virual address
        try await self.testMiddleware(S3Middleware(), uri: "/bucket/file") { request in
            #expect(request.request.url?.absoluteString == "https://bucket.service.us-east-1.amazonaws.com/file")
        }
    }

    @Test func testS3MiddlewareVirtualAddressWithSlash() async throws {
        // Test virual address
        try await self.testMiddleware(S3Middleware(), uri: "/bucket/file/sdf/") { request in
            #expect(request.request.url?.absoluteString == "https://bucket.service.us-east-1.amazonaws.com/file/sdf/")
        }
    }

    @Test func testS3MiddlewareVirtualAddressWithPercentEncoding() async throws {
        // Test virual address
        try await self.testMiddleware(S3Middleware(), uri: "/bucket/file%26") { request in
            #expect(request.request.url?.absoluteString == "https://bucket.service.us-east-1.amazonaws.com/file%26")
        }
    }

    @Test func testS3MiddlewareAccelerateEndpoint() async throws {
        // Test virual address
        try await self.testMiddleware(
            S3Middleware(),
            serviceName: "s3",
            serviceOptions: .s3UseTransferAcceleratedEndpoint,
            uri: "/bucket/file"
        ) { request in
            #expect(request.request.url?.absoluteString == "https://bucket.s3-accelerate.amazonaws.com/file")
        }
    }

    @Test func testS3MiddlewareErrorFixup() async throws {
        struct ThrowNotFoundErrorMiddleware: AWSMiddlewareProtocol {
            public func handle(
                _ request: AWSHTTPRequest,
                context: AWSMiddlewareContext,
                next: (AWSHTTPRequest, AWSMiddlewareContext) async throws -> AWSHTTPResponse
            ) async throws -> AWSHTTPResponse {
                throw AWSRawError(rawBody: nil, context: .init(message: "NotFound", response: HTTPResponse(status: .notFound)))
            }
        }
        // Test virual address
        let error = await #expect(throws: S3TestErrorType.self) {
            try await self.testServiceConfig(
                createServiceConfig(
                    errorType: S3TestErrorType.self,
                    middlewares: AWSMiddlewareStack {
                        S3Middleware()
                        ThrowNotFoundErrorMiddleware()
                    }
                ),
                uri: "/bucket/file"
            ) { _ in
            }
        }
        switch error {
        case .notFound:
            break
        default:
            Issue.record("Throwing wrong error: \(error)")
        }
    }

    @Test func testS3MiddlewareAccessPointArn() async throws {
        // Test virual address
        try await self.testMiddleware(
            S3Middleware(),
            serviceName: "s3",
            serviceOptions: .s3UseTransferAcceleratedEndpoint,
            uri: "/arn:aws:s3:us-west-2:111122223333:accesspoint/test-accesspoint"
        ) { request in
            #expect(
                request.request.url?.absoluteString == "https://test-accesspoint-111122223333.s3-accesspoint.us-west-2.amazonaws.com/"
            )
        }
    }

    @Test func testS3MiddlewareObjectLambdaArn() async throws {
        // Test virual address
        try await self.testMiddleware(
            S3Middleware(),
            serviceName: "s3",
            serviceOptions: .s3UseTransferAcceleratedEndpoint,
            uri: "/arn:aws:s3-object-lambda:us-west-2:111122223333:accesspoint/tutorial-object-lambda-accesspoint/file"
        ) { request in
            #expect(
                request.request.url?.absoluteString
                    == "https://tutorial-object-lambda-accesspoint-111122223333.s3-object-lambda.us-west-2.amazonaws.com/file"
            )
        }
    }

    @Test func testS3MiddlewareS3ExpressEndpoint() async throws {
        // Test virual address
        try await self.testMiddleware(
            S3Middleware(),
            serviceName: "s3",
            uri: "/s3express--bucket--use1-az6--x-s3/file"
        ) { request in
            #expect(
                request.request.url?.absoluteString == "https://s3express--bucket--use1-az6--x-s3.s3express-use1-az6.us-east-1.amazonaws.com/file"
            )
        }
    }

    @Test func testS3MiddlewareS3ExpressControlEndpoint() async throws {
        // Test virual address
        try await S3Middleware.$executionContext.withValue(.init(useS3ExpressControlEndpoint: true)) {
            try await self.testMiddleware(
                S3Middleware(),
                serviceName: "s3",
                uri: "/s3express--bucket--use1-az6--x-s3/"
            ) { request in
                #expect(
                    request.request.url?.absoluteString == "https://s3express-control.us-east-1.amazonaws.com/s3express--bucket--use1-az6--x-s3/"
                )
            }
        }
    }

    // create a buffer of random values. Will always create the same given you supply the same z and w values
    // Random number generator from https://www.codeproject.com/Articles/25172/Simple-Random-Number-Generation
    func createRandomBuffer(_ w: UInt, _ z: UInt, size: Int) -> [UInt8] {
        var z = z
        var w = w
        func getUInt8() -> UInt8 {
            z = 36969 * (z & 65535) + (z >> 16)
            w = 18000 * (w & 65535) + (w >> 16)
            return UInt8(((z << 16) + w) & 0xFF)
        }
        var data = [UInt8](repeating: 0, count: size)
        for i in 0..<size {
            data[i] = getUInt8()
        }
        return data
    }

    @Test func testComputeTreeHash() throws {
        //  create buffer full of random data, use the same seeds to ensure we get the same buffer everytime
        let data = self.createRandomBuffer(23, 4, size: 7 * 1024 * 1024 + 258)

        // create byte buffer
        var byteBuffer = ByteBufferAllocator().buffer(capacity: data.count)
        byteBuffer.writeBytes(data)

        let middleware = TreeHashMiddleware(header: HTTPField.Name("tree-hash")!)
        let treeHash = try middleware.computeTreeHash(byteBuffer)

        #expect(
            treeHash == [
                210, 50, 5, 126, 16, 6, 59, 6, 21, 40, 186, 74, 192, 56, 39, 85, 210, 25, 238, 54, 4, 252, 221, 238, 107, 127, 76, 118, 245, 76, 22,
                45,
            ]
        )
    }

    struct S3TestErrorType: AWSErrorType, Equatable {
        enum Code: String {
            case notFound = "NotFound"
        }

        private let error: Code
        let context: AWSErrorContext?

        /// initialize S3
        init?(errorCode: String, context: AWSErrorContext) {
            guard let error = Code(rawValue: errorCode) else { return nil }
            self.error = error
            self.context = context
        }

        internal init(_ error: Code) {
            self.error = error
            self.context = nil
        }

        /// return error code string
        var errorCode: String { self.error.rawValue }

        static var notFound: Self { .init(.notFound) }

        var description: String {
            "\(self.error.rawValue): \(self.message ?? "")"
        }

        static func == (lhs: S3TestErrorType, rhs: S3TestErrorType) -> Bool {
            lhs.error == rhs.error
        }
    }
}
