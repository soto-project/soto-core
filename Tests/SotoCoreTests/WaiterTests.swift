//===----------------------------------------------------------------------===//
//
// This source file is part of the Soto for AWS open source project
//
// Copyright (c) 2017-2021 the Soto project authors
// Licensed under Apache License v2.0
//
// See LICENSE.txt for license information
// See CONTRIBUTORS.txt for the list of Soto project authors
//
// SPDX-License-Identifier: Apache-2.0
//
//===----------------------------------------------------------------------===//

import AsyncHTTPClient
import NIO
@testable import SotoCore
import SotoTestUtils
import XCTest

class WaiterTests: XCTestCase {
    func testBasicWaiter() {
        let awsServer = AWSTestServer(serviceProtocol: .json)
        let config = createServiceConfig(serviceProtocol: .json(version: "1.1"), endpoint: awsServer.address)
        let client = createAWSClient(credentialProvider: .empty, middlewares: [AWSLoggingMiddleware()])
        defer {
            XCTAssertNoThrow(try client.syncShutdown())
            XCTAssertNoThrow(try awsServer.stop())
        }

        struct Input: AWSEncodableShape & Decodable {
            let i: Int
        }
        struct Output: AWSDecodableShape & Encodable {
            let i: Int
        }
        func operation(input: Input, logger: Logger, eventLoop: EventLoop?) -> EventLoopFuture<Output> {
            client.execute(operation: "Basic", path: "/", httpMethod: .POST, serviceConfig: config, input: input, logger: logger, on: eventLoop)
        }
        let waiter = AWSClient.Waiter(
            acceptors: [.init(state: .success, matcher: AWSOutputMatcher(path: \Output.i, expected: 3))],
            maxRetryAttempts: 20,
            command: operation
        )
        do {
            let input = Input(i: 1)
            let response = client.wait(input, waiter: waiter, maxWaitTime: .seconds(20), logger: TestEnvironment.logger)

            var i = 0
            try awsServer.process { (request: Input) -> AWSTestServer.Result<Output> in
                //let receivedInput = try JSONDecoder().decode(Input.self, from: request.body)
                i += 1
                return .result(Output(i: i), continueProcessing: i < 3)
            }

            try response.wait()
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

}
