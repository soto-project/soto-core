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

@testable import SotoCore
import SotoTestUtils
import XCTest

class MiddlewareTests: XCTestCase {
    struct CatchRequestError: Error {
        let request: AWSHTTPRequest
    }

    struct CatchRequestMiddleware: AWSMiddlewareProtocol {
        func handle(_ request: AWSHTTPRequest, context: AWSMiddlewareContext, next: (AWSHTTPRequest, AWSMiddlewareContext) async throws -> AWSHTTPResponse) async throws -> AWSHTTPResponse {
            throw CatchRequestError(request: request)
        }
    }

    func testMiddleware<Middleware: AWSMiddlewareProtocol>(
        _ middleware: Middleware,
        serviceName: String = "service",
        serviceOptions: AWSServiceConfig.Options = [],
        uri: String = "/",
        test: (AWSHTTPRequest) -> Void
    ) async throws {
        let client = createAWSClient(credentialProvider: .empty)
        let config = createServiceConfig(
            region: .useast1,
            endpoint: "https://\(serviceName).us-east-1.amazonaws.com",
            middlewares: AWSMiddlewareStack {
                middleware
                CatchRequestMiddleware()
            },
            options: serviceOptions
        )
        do {
            _ = try await client.execute(operation: "test", path: uri, httpMethod: .POST, serviceConfig: config, logger: TestEnvironment.logger)
            XCTFail("Should not get here")
        } catch {
            let error = try XCTUnwrap(error as? CatchRequestError)
            test(error.request)
        }
        try await client.shutdown()
    }

    func testMiddlewareAppliedOnce() async throws {
        struct URLAppendMiddleware: AWSMiddlewareProtocol {
            func handle(_ request: AWSHTTPRequest, context: AWSMiddlewareContext, next: (AWSHTTPRequest, AWSMiddlewareContext) async throws -> AWSHTTPResponse) async throws -> AWSHTTPResponse {
                var request = request
                request.url.appendPathComponent("test")
                return try await next(request, context)
            }
        }

        let awsServer = AWSTestServer(serviceProtocol: .json)
        let config = createServiceConfig(endpoint: awsServer.address)
        let client = createAWSClient(credentialProvider: .empty, middlewares: URLAppendMiddleware())
        defer {
            XCTAssertNoThrow(try client.syncShutdown())
            XCTAssertNoThrow(try awsServer.stop())
        }

        async let responseTask: Void = client.execute(operation: "test", path: "/", httpMethod: .POST, serviceConfig: config, logger: TestEnvironment.logger)

        XCTAssertNoThrow(try awsServer.processRaw { request in
            XCTAssertEqual(request.uri, "/test")
            return .result(AWSTestServer.Response.ok)
        })

        try await responseTask
    }

    func testEditHeaderMiddlewareAddHeader() async throws {
        // Test add header
        let middleware = AWSEditHeadersMiddleware(
            .add(name: "testAdd", value: "testValue"),
            .add(name: "user-agent", value: "testEditHeaderMiddleware")
        )
        try await self.testMiddleware(middleware) { request in
            XCTAssertEqual(request.headers["testAdd"].first, "testValue")
            XCTAssertEqual(request.headers["user-agent"].joined(separator: ","), "Soto/6.0,testEditHeaderMiddleware")
        }
    }

    func testEditHeaderMiddlewareReplaceHeader() async throws {
        // Test replace header
        let middleware = AWSEditHeadersMiddleware(
            .replace(name: "user-agent", value: "testEditHeaderMiddleware")
        )
        try await self.testMiddleware(middleware) { request in
            XCTAssertEqual(request.headers["user-agent"].first, "testEditHeaderMiddleware")
        }
    }

    func testS3MiddlewareVirtualAddress() async throws {
        // Test virual address
        try await self.testMiddleware(S3Middleware(), uri: "/bucket/file") { request in
            XCTAssertEqual(request.url.absoluteString, "https://bucket.service.us-east-1.amazonaws.com/file")
        }
    }

    func testS3MiddlewareAccelerateEndpoint() async throws {
        // Test virual address
        try await self.testMiddleware(
            S3Middleware(),
            serviceName: "s3",
            serviceOptions: .s3UseTransferAcceleratedEndpoint,
            uri: "/bucket/file"
        ) { request in
            XCTAssertEqual(request.url.absoluteString, "https://bucket.s3-accelerate.amazonaws.com/file")
        }
    }

    func testS3MiddlewareErrorFixup() async throws {
        struct ThrowNotFoundErrorMiddleware: AWSMiddlewareProtocol {
            public func handle(_ request: AWSHTTPRequest, context: AWSMiddlewareContext, next: (AWSHTTPRequest, AWSMiddlewareContext) async throws -> AWSHTTPResponse) async throws -> AWSHTTPResponse {
                throw AWSRawError(rawBody: nil, context: .init(message: "NotFound", responseCode: .notFound))
            }
        }
        let client = createAWSClient(credentialProvider: .empty)
        let config = createServiceConfig(
            region: .useast1,
            endpoint: "https://test.us-east-1.amazonaws.com",
            errorType: S3TestErrorType.self,
            middlewares: AWSMiddlewareStack {
                S3Middleware()
                ThrowNotFoundErrorMiddleware()
            }
        )
        do {
            _ = try await client.execute(operation: "test", path: "/", httpMethod: .POST, serviceConfig: config, logger: TestEnvironment.logger)
            XCTFail("Should not get here")
        } catch let error as S3TestErrorType where error == .notFound {
        } catch {
            XCTFail("Throwing wrong error: \(error)")
        }
        try await client.shutdown()
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

    func testComputeTreeHash() throws {
        //  create buffer full of random data, use the same seeds to ensure we get the same buffer everytime
        let data = self.createRandomBuffer(23, 4, size: 7 * 1024 * 1024 + 258)

        // create byte buffer
        var byteBuffer = ByteBufferAllocator().buffer(capacity: data.count)
        byteBuffer.writeBytes(data)

        let middleware = TreeHashMiddleware(header: "tree-hash")
        let treeHash = try middleware.computeTreeHash(byteBuffer)

        XCTAssertEqual(
            treeHash,
            [210, 50, 5, 126, 16, 6, 59, 6, 21, 40, 186, 74, 192, 56, 39, 85, 210, 25, 238, 54, 4, 252, 221, 238, 107, 127, 76, 118, 245, 76, 22, 45]
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
            return "\(self.error.rawValue): \(self.message ?? "")"
        }

        static func == (lhs: S3TestErrorType, rhs: S3TestErrorType) -> Bool {
            lhs.error == rhs.error
        }
    }
}
