//===----------------------------------------------------------------------===//
//
// This source file is part of the AWSSDKSwift open source project
//
// Copyright (c) 2017-2020 the AWSSDKSwift project authors
// Licensed under Apache License v2.0
//
// See LICENSE.txt for license information
// See CONTRIBUTORS.txt for the list of AWSSDKSwift project authors
//
// SPDX-License-Identifier: Apache-2.0
//
//===----------------------------------------------------------------------===//

@testable import AWSSDKSwiftCore
import AWSTestUtils
import Baggage
import Instrumentation
import Logging
import NIO
import NIOHTTP1
import XCTest

class TracingTests: XCTestCase {
    func testTracingDownstreamCall() {
        // bootstrap tracer
        let tracer = TestTracer()
        InstrumentationSystem.bootstrap(tracer)

        let awsServer = AWSTestServer(serviceProtocol: .json)
        let eventLoopGroup = MultiThreadedEventLoopGroup(numberOfThreads: 1)
        defer {
            XCTAssertNoThrow(try awsServer.stop())
            XCTAssertNoThrow(try eventLoopGroup.syncShutdownGracefully())
        }
        let config = createServiceConfig(
            serviceProtocol: .json(version: "1.1"),
            endpoint: awsServer.address
        )
        let client = createAWSClient(
            credentialProvider: .static(accessKeyId: "foo", secretAccessKey: "bar"),
            httpClientProvider: .createNew
        )
        defer {
            XCTAssertNoThrow(try client.syncShutdown())
        }

        // execute the query
        let response: EventLoopFuture<AWSTestServer.HTTPBinResponse> = client.execute(
            operation: "test",
            path: "/",
            httpMethod: .POST,
            serviceConfig: config,
            context: TestEnvironment.context
        )
        XCTAssertNoThrow(try awsServer.httpBin())
        XCTAssertNoThrow(try response.wait())

        // flush the tracer and check what have been recorded
        tracer.forceFlush()
        let spans = tracer._test_recordedSpans
        XCTAssertGreaterThan(spans.count, 0)
        // TODO: extend
        let span = spans.first { $0._test_operationName == "invoke" }
        XCTAssertNotNil(span)
        XCTAssertNotNil(span?._test_endTimestamp)
        XCTAssertEqual(span?._test_errors.count, 0)
    }
}
