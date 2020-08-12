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

import AWSSDKSwiftCore
import AWSTestUtils
import XCTest

class AWSServiceTests: XCTestCase {
    var client: AWSClient!

    override func setUp() {
        self.client = createAWSClient()
    }

    override func tearDown() {
        XCTAssertNoThrow(try self.client.syncShutdown())
    }

    func testRegion() {
        let service = TestService(client: client, config: createServiceConfig(region: .eucentral1), context: .init())
        XCTAssertEqual(service.region, .eucentral1)
    }

    func testEndpoint() {
        let endpoint = "https://myendpoint:8000"
        let service = TestService(client: client, config: createServiceConfig(endpoint: endpoint), context: .init())
        XCTAssertEqual(service.endpoint, endpoint)
    }

    func testDelegatingToEventloop() {
        let service = TestService(client: client, config: createServiceConfig(), context: .init())
        let eventLoop = service.eventLoopGroup.next()
        XCTAssertNil(service.context.eventLoop)
        XCTAssertTrue(service.delegating(to: eventLoop).context.eventLoop === eventLoop)
    }

    func testTimeout() {
        let service = TestService(client: client, config: createServiceConfig(), context: .init(timeout: .seconds(23)))
        XCTAssertEqual(service.context.timeout, .seconds(23))
        XCTAssertEqual(service.timingOut(after: .seconds(34)).context.timeout, .seconds(34))
    }

    func testLogger() {
        let service = TestService(client: client, config: createServiceConfig(), context: .init())
        XCTAssertEqual(service.context.logger.label, AWSClient.loggingDisabled.label)
        XCTAssertEqual(service.logging(to: Logger(label: "TestLogger")).context.logger.label, "TestLogger")
    }
}

struct TestService: AWSService {
    var client: AWSClient
    var config: AWSServiceConfig
    var context: AWSServiceContext

    func withNewContext(_ process: (AWSServiceContext) -> AWSServiceContext) -> Self {
        return Self(client: self.client, config: self.config, context: process(self.context))
    }
}
