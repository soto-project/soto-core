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
        let request: AWSRequest
    }

    struct CatchRequestMiddleware: AWSServiceMiddleware {
        func chain(request: AWSRequest, context: AWSMiddlewareContext) throws -> AWSRequest {
            throw CatchRequestError(request: request)
        }
    }

    func testMiddleware<Middleware: AWSServiceMiddleware>(
        _ middleware: Middleware,
        serviceName: String = "service",
        serviceOptions: AWSServiceConfig.Options = [],
        uri: String = "/",
        test: (AWSRequest) -> Void
    ) {
        let client = createAWSClient(credentialProvider: .empty)
        let config = createServiceConfig(
            region: .useast1,
            endpoint: "https://\(serviceName).us-east-1.amazonaws.com",
            middlewares: [middleware, CatchRequestMiddleware()],
            options: serviceOptions
        )
        let response = client.execute(operation: "test", path: uri, httpMethod: .POST, serviceConfig: config, logger: TestEnvironment.logger)
        XCTAssertThrowsError(try response.wait()) { error in
            if let error = error as? CatchRequestError {
                test(error.request)
            }
        }
        try? client.syncShutdown()
    }

    func testMiddlewareAppliedOnce() {
        struct URLAppendMiddleware: AWSServiceMiddleware {
            func chain(request: AWSRequest, context: AWSMiddlewareContext) throws -> AWSRequest {
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

        let response = client.execute(operation: "test", path: "/", httpMethod: .POST, serviceConfig: config, logger: TestEnvironment.logger)

        XCTAssertNoThrow(try awsServer.processRaw { request in
            XCTAssertEqual(request.uri, "/test")
            return .result(AWSTestServer.Response.ok)
        })

        XCTAssertNoThrow(try response.wait())
    }

    func testEditHeaderMiddlewareAddHeader() {
        // Test add header
        let middleware = AWSEditHeadersMiddleware(
            .add(name: "testAdd", value: "testValue"),
            .add(name: "user-agent", value: "testEditHeaderMiddleware")
        )
        self.testMiddleware(middleware) { request in
            XCTAssertEqual(request.httpHeaders["testAdd"].first, "testValue")
            XCTAssertEqual(request.httpHeaders["user-agent"].joined(separator: ","), "Soto/6.0,testEditHeaderMiddleware")
        }
    }

    func testEditHeaderMiddlewareReplaceHeader() {
        // Test replace header
        let middleware = AWSEditHeadersMiddleware(
            .replace(name: "user-agent", value: "testEditHeaderMiddleware")
        )
        self.testMiddleware(middleware) { request in
            XCTAssertEqual(request.httpHeaders["user-agent"].first, "testEditHeaderMiddleware")
        }
    }

    func testS3MiddlewareVirtualAddress() {
        // Test virual address
        self.testMiddleware(S3Middleware(), uri: "/bucket/file") { request in
            XCTAssertEqual(request.url.absoluteString, "https://bucket.service.us-east-1.amazonaws.com/file")
        }
    }

    func testS3MiddlewareAccelerateEndpoint() {
        // Test virual address
        self.testMiddleware(
            S3Middleware(),
            serviceName: "s3",
            serviceOptions: .s3UseTransferAcceleratedEndpoint,
            uri: "/bucket/file"
        ) { request in
            XCTAssertEqual(request.url.absoluteString, "https://bucket.s3-accelerate.amazonaws.com/file")
        }
    }

    func testS3MiddlewareDualStackEndpoint() {
        // Test virual address
        self.testMiddleware(
            S3Middleware(),
            serviceName: "s3",
            serviceOptions: .s3UseDualStackEndpoint,
            uri: "/bucket/file"
        ) { request in
            XCTAssertEqual(request.url.absoluteString, "https://bucket.s3.dualstack.us-east-1.amazonaws.com/file")
        }
    }

    func testS3MiddlewareAcceleratedDualStackEndpoint() {
        // Test virual address
        self.testMiddleware(
            S3Middleware(),
            serviceName: "s3",
            serviceOptions: [.s3UseDualStackEndpoint, .s3UseTransferAcceleratedEndpoint],
            uri: "/bucket/file"
        ) { request in
            XCTAssertEqual(request.url.absoluteString, "https://bucket.s3-accelerate.dualstack.amazonaws.com/file")
        }
    }
}
