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

@available(macOS 10.15, iOS 13.0, tvOS 13.0, watchOS 6.0, *)
final class WaiterAsyncTests: XCTestCase, @unchecked Sendable {
    var awsServer: AWSTestServer!
    var config: AWSServiceConfig!
    var client: AWSClient!

    override func setUp() {
        self.awsServer = AWSTestServer(serviceProtocol: .json)
        self.config = createServiceConfig(serviceProtocol: .json(version: "1.1"), endpoint: self.awsServer.address)
        self.client = createAWSClient(credentialProvider: .empty, middlewares: [AWSLoggingMiddleware()])
    }

    override func tearDown() {
        XCTAssertNoThrow(try self.client.syncShutdown())
        XCTAssertNoThrow(try self.awsServer.stop())
    }

    struct Input: AWSEncodableShape & Decodable {}

    struct ArrayOutput: AWSDecodableShape & Encodable {
        struct Element: AWSDecodableShape & Encodable, ExpressibleByBooleanLiteral {
            let status: Bool
            init(booleanLiteral: Bool) {
                self.status = booleanLiteral
            }

            init(_ status: Bool) {
                self.status = status
            }
        }

        let array: [Element]
    }

    func arrayOperation(input: Input, logger: Logger, eventLoop: EventLoop?) -> EventLoopFuture<ArrayOutput> {
        self.client.execute(operation: "Basic", path: "/", httpMethod: .POST, serviceConfig: self.config, input: input, logger: logger, on: eventLoop)
    }

    func testJMESPathWaiter() async throws {
        #if os(iOS) // iOS async tests are failing in GitHub CI at the moment
        guard ProcessInfo.processInfo.environment["CI"] == nil else { return }
        #endif
        let waiter = AWSClient.Waiter(
            acceptors: [
                .init(state: .success, matcher: try! JMESPathMatcher("array[*].status", expected: [true, true, true])),
            ],
            minDelayTime: .seconds(2),
            command: self.arrayOperation
        )
        let input = Input()
        async let asyncWait: Void = self.client.waitUntil(input, waiter: waiter, logger: TestEnvironment.logger)

        var i = 0
        try self.awsServer.process { (_: Input) -> AWSTestServer.Result<ArrayOutput> in
            i += 1
            return .result(ArrayOutput(array: [.init(i >= 3), .init(i >= 2), .init(i >= 1)]), continueProcessing: i < 3)
        }

        try await asyncWait
    }
}
