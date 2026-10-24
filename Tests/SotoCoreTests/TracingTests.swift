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

import Foundation
import HTTPTypes
import InMemoryTracing
import NIOHTTP1
import NIOPosix
import SotoCore
import SotoTestUtils
import Testing
import Tracing

@testable import Instrumentation

struct TracingTests {
    @Test func testTracingMiddleware() async throws {
        let tracer = InMemoryTracer()

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
            #expect(throws: Never.self) { try client.syncShutdown() }
            #expect(throws: Never.self) { try awsServer.stop() }
        }
        async let response: Void = client.execute(
            operation: "TestOperation",
            path: "/",
            httpMethod: .post,
            serviceConfig: config,
            logger: TestEnvironment.logger
        )

        try awsServer.processRaw { _ in
            let response = AWSTestServer.Response(httpStatus: .ok, headers: ["x-amz-request-id": "test-request-1"], body: nil)
            return .result(response)
        }

        _ = try await response

        let spans = tracer.popFinishedSpans()
        // We should get two spans. One from AsyncHTTPClient and one from Soto. The second one is the Soto one
        let span = try #require(spans.last)

        #expect(span.operationName == "TestService.TestOperation")
        #expect(span.errors.isEmpty)

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
    sourceLocation: SourceLocation = #_sourceLocation
) {
    var rhs = rhs()

    lhs().forEach { key, attribute in
        if let rhsValue = rhs.removeValue(forKey: key) {
            if rhsValue != attribute {
                Issue.record(
                    #""\#(key)" was expected to be "\#(rhsValue)" but is actually "\#(attribute)"."#,
                    sourceLocation: sourceLocation
                )
            }
        } else {
            Issue.record(
                #"Did not specify expected value for "\#(key)", actual value is "\#(attribute)"."#,
                sourceLocation: sourceLocation
            )
        }
    }

    if !rhs.isEmpty {
        Issue.record(#"Expected attributes "\#(rhs.keys)" are not present in actual attributes."#, sourceLocation: sourceLocation)
    }
}
