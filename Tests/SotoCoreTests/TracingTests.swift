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

import NIOPosix
import SotoCore
import SotoTestUtils
import Tracing
import XCTest

@testable import Instrumentation

final class TracingTests: XCTestCase {
    func wait(for expectations: [XCTestExpectation], timeout: TimeInterval) async {
        await fulfillment(of: expectations, timeout: timeout)
    }

    func testTracingMiddleware() async throws {
        let expectation = expectation(description: "Expected span to be ended.")

        let tracer = TestTracer {
            _ in expectation.fulfill()
        }
        InstrumentationSystem.bootstrapInternal(tracer)

        let awsServer = AWSTestServer(serviceProtocol: .json)
        let config = createServiceConfig(
            service: "TestService",
            serviceProtocol: .json(version: "1.1"),
            endpoint: awsServer.address,
            middlewares: AWSTracingMiddleware()
        )
        let client = createAWSClient(
            credentialProvider: .empty
        )
        defer {
            XCTAssertNoThrow(try client.syncShutdown())
            XCTAssertNoThrow(try awsServer.stop())
        }
        async let response: Void = client.execute(
            operation: "TestOperation",
            path: "/",
            httpMethod: .POST,
            serviceConfig: config,
            logger: TestEnvironment.logger
        )

        try awsServer.processRaw { _ in
            let response = AWSTestServer.Response(httpStatus: .ok, headers: ["x-amz-request-id": "test-request-1"], body: nil)
            return .result(response)
        }

        _ = try await response

        await self.wait(for: [expectation], timeout: 1.0)

        let span = try tracer.spans.withLockedValue {
            try XCTUnwrap($0.first)
        }

        XCTAssertEqual(span.operationName, "TestService.TestOperation")
        XCTAssertTrue(span.recordedErrors.isEmpty)

        XCTAssertSpanAttributesEqual(
            span.attributes,
            [
                "rpc.system": "aws-sdk",
                "rpc.method": "TestOperation",
                "rpc.service": "TestService",
                "aws.request_id": "test-request-1",
            ]
        )
    }
}

private func XCTAssertSpanAttributesEqual(
    _ lhs: @autoclosure () -> SpanAttributes,
    _ rhs: @autoclosure () -> [String: SpanAttribute],
    file: StaticString = #filePath,
    line: UInt = #line
) {
    var rhs = rhs()

    lhs().forEach { key, attribute in
        if let rhsValue = rhs.removeValue(forKey: key) {
            if rhsValue != attribute {
                XCTFail(
                    #""\#(key)" was expected to be "\#(rhsValue)" but is actually "\#(attribute)"."#,
                    file: file,
                    line: line
                )
            }
        } else {
            XCTFail(
                #"Did not specify expected value for "\#(key)", actual value is "\#(attribute)"."#,
                file: file,
                line: line
            )
        }
    }

    if !rhs.isEmpty {
        XCTFail(#"Expected attributes "\#(rhs.keys)" are not present in actual attributes."#, file: file, line: line)
    }
}
