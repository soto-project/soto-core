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
import SotoCore
import SotoTestUtils
import XCTest

class WaiterTests: XCTestCase {
    static var awsServer: AWSTestServer!
    static var config: AWSServiceConfig!
    static var client: AWSClient!

    override class func setUp() {
        Self.awsServer = AWSTestServer(serviceProtocol: .json)
        Self.config = createServiceConfig(serviceProtocol: .json(version: "1.1"), endpoint: self.awsServer.address)
        Self.client = createAWSClient(credentialProvider: .empty, middlewares: [AWSLoggingMiddleware()])
    }

    override class func tearDown() {
        XCTAssertNoThrow(try self.client.syncShutdown())
        XCTAssertNoThrow(try self.awsServer.stop())
    }

    struct Input: AWSEncodableShape & Decodable {}

    struct Output: AWSDecodableShape & Encodable {
        let i: Int
    }

    func operation(input: Input, logger: Logger, eventLoop: EventLoop?) -> EventLoopFuture<Output> {
        Self.client.execute(operation: "Basic", path: "/", httpMethod: .POST, serviceConfig: Self.config, input: input, logger: logger, on: eventLoop)
    }

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
        Self.client.execute(operation: "Basic", path: "/", httpMethod: .POST, serviceConfig: Self.config, input: input, logger: logger, on: eventLoop)
    }

    struct OptionalArrayOutput: AWSDecodableShape & Encodable {
        struct Element: AWSDecodableShape & Encodable, ExpressibleByBooleanLiteral {
            let status: Bool
            init(booleanLiteral: Bool) {
                self.status = booleanLiteral
            }
        }

        let array: [Element]?
    }

    func optionalArrayOperation(input: Input, logger: Logger, eventLoop: EventLoop?) -> EventLoopFuture<OptionalArrayOutput> {
        Self.client.execute(operation: "Basic", path: "/", httpMethod: .POST, serviceConfig: Self.config, input: input, logger: logger, on: eventLoop)
    }

    func testJMESPathWaiter() {
        let waiter = AWSClient.Waiter(
            acceptors: [
                .init(state: .success, matcher: try! JMESPathMatcher("array[*].status", expected: [true, true, true])),
            ],
            minDelayTime: .seconds(2),
            command: self.arrayOperation
        )
        let input = Input()
        let response = Self.client.waitUntil(input, waiter: waiter, logger: TestEnvironment.logger)

        var i = 0
        XCTAssertNoThrow(try Self.awsServer.process { (_: Input) -> AWSTestServer.Result<ArrayOutput> in
            i += 1
            return .result(ArrayOutput(array: [.init(i >= 3), .init(i >= 2), .init(i >= 1)]), continueProcessing: i < 3)
        })

        XCTAssertNoThrow(try response.wait())
    }

    func testJMESPathWaiterWithString() {
        struct StringOutput: AWSDecodableShape & Encodable {
            let s: String
        }
        func operation(input: Input, logger: Logger, eventLoop: EventLoop?) -> EventLoopFuture<StringOutput> {
            Self.client.execute(operation: "Basic", path: "/", httpMethod: .POST, serviceConfig: Self.config, input: input, logger: logger, on: eventLoop)
        }
        let waiter = AWSClient.Waiter(
            acceptors: [
                .init(state: .success, matcher: try! JMESPathMatcher("s", expected: "yes")),
            ],
            minDelayTime: .seconds(2),
            command: operation
        )
        let input = Input()
        let response = Self.client.waitUntil(input, waiter: waiter, logger: TestEnvironment.logger)

        var i = 0
        XCTAssertNoThrow(try Self.awsServer.process { (_: Input) -> AWSTestServer.Result<StringOutput> in
            i += 1
            if i < 2 {
                return .result(.init(s: "no"), continueProcessing: true)
            } else {
                return .result(.init(s: "yes"), continueProcessing: false)
            }
        })

        XCTAssertNoThrow(try response.wait())
    }

    func testJMESPathWaiterWithEnum() {
        enum YesNo: String, AWSDecodableShape & Encodable & CustomStringConvertible {
            case yes = "YES"
            case no = "NO"
            var description: String { return self.rawValue }
        }
        struct EnumOutput: AWSDecodableShape & Encodable {
            let e: YesNo
        }
        func operation(input: Input, logger: Logger, eventLoop: EventLoop?) -> EventLoopFuture<EnumOutput> {
            Self.client.execute(operation: "Basic", path: "/", httpMethod: .POST, serviceConfig: Self.config, input: input, logger: logger, on: eventLoop)
        }
        let waiter = AWSClient.Waiter(
            acceptors: [
                .init(state: .success, matcher: try! JMESPathMatcher("e", expected: "YES")),
            ],
            minDelayTime: .seconds(2),
            command: operation
        )
        let input = Input()
        let response = Self.client.waitUntil(input, waiter: waiter, logger: TestEnvironment.logger)

        var i = 0
        XCTAssertNoThrow(try Self.awsServer.process { (_: Input) -> AWSTestServer.Result<EnumOutput> in
            i += 1
            if i < 2 {
                return .result(.init(e: .no), continueProcessing: true)
            } else {
                return .result(.init(e: .yes), continueProcessing: false)
            }
        })

        XCTAssertNoThrow(try response.wait())
    }

    func testJMESAnyPathWaiter() {
        let waiter = AWSClient.Waiter(
            acceptors: [
                .init(state: .success, matcher: try! JMESAnyPathMatcher("array[*].status", expected: true)),
            ],
            minDelayTime: .seconds(2),
            command: self.arrayOperation
        )
        let input = Input()
        let response = Self.client.waitUntil(input, waiter: waiter, logger: TestEnvironment.logger)

        var i = 0
        XCTAssertNoThrow(try Self.awsServer.process { (_: Input) -> AWSTestServer.Result<ArrayOutput> in
            i += 1
            if i < 2 {
                return .result(ArrayOutput(array: [false, false, false]), continueProcessing: true)
            } else {
                return .result(ArrayOutput(array: [false, true, false]), continueProcessing: false)
            }
        })

        XCTAssertNoThrow(try response.wait())
    }

    func testJMESAllPathWaiter() {
        let waiter = AWSClient.Waiter(
            acceptors: [
                .init(state: .success, matcher: try! JMESAllPathMatcher("array[*].status", expected: true)),
            ],
            minDelayTime: .seconds(2),
            command: self.arrayOperation
        )
        let input = Input()
        let response = Self.client.waitUntil(input, waiter: waiter, logger: TestEnvironment.logger)

        var i = 0
        XCTAssertNoThrow(try Self.awsServer.process { (_: Input) -> AWSTestServer.Result<ArrayOutput> in
            i += 1
            if i < 2 {
                return .result(ArrayOutput(array: [false, true, false]), continueProcessing: true)
            } else {
                return .result(ArrayOutput(array: [true, true, true]), continueProcessing: false)
            }
        })

        XCTAssertNoThrow(try response.wait())
    }

    func testJMESPathPropertyValueWaiter() {
        struct ArrayOutput: AWSDecodableShape & Encodable {
            @CustomCoding<StandardArrayCoder<Bool>> var array: [Bool]
        }
        struct Input: AWSEncodableShape & Decodable {
            let test: String
        }
        let awsServer = AWSTestServer(serviceProtocol: .xml)
        defer { XCTAssertNoThrow(try awsServer.stop()) }
        let config = createServiceConfig(serviceProtocol: .restxml, endpoint: awsServer.address)

        func arrayOperation(input: Input, logger: Logger, eventLoop: EventLoop?) -> EventLoopFuture<ArrayOutput> {
            Self.client.execute(operation: "Basic", path: "/", httpMethod: .POST, serviceConfig: config, input: input, logger: logger, on: eventLoop)
        }

        let waiter = AWSClient.Waiter(
            acceptors: [
                .init(state: .success, matcher: try! JMESPathMatcher("array[*]", expected: [true, true, true])),
            ],
            minDelayTime: .seconds(2),
            command: arrayOperation
        )
        let input = Input(test: "Input")
        let response = Self.client.waitUntil(input, waiter: waiter, logger: TestEnvironment.logger)

        var i = 0
        XCTAssertNoThrow(try awsServer.process { (_: Input) -> AWSTestServer.Result<ArrayOutput> in
            i += 1
            return .result(ArrayOutput(array: [.init(i >= 3), .init(i >= 2), .init(i >= 1)]), continueProcessing: i < 3)
        })

        XCTAssertNoThrow(try response.wait())
    }

    func testTimeoutWaiter() {
        let waiter = AWSClient.Waiter(
            acceptors: [
                .init(state: .success, matcher: try! JMESPathMatcher("i", expected: 3)),
            ],
            minDelayTime: .seconds(2),
            maxDelayTime: .seconds(4),
            command: self.operation
        )
        let input = Input()
        let response = Self.client.waitUntil(input, waiter: waiter, maxWaitTime: .seconds(4), logger: TestEnvironment.logger)

        var i = 0
        XCTAssertNoThrow(try Self.awsServer.process { (_: Input) -> AWSTestServer.Result<Output> in
            i += 1
            return .result(Output(i: i), continueProcessing: i < 2)
        })

        XCTAssertThrowsError(try response.wait()) { error in
            switch error {
            case let error as AWSClient.ClientError where error == .waiterTimeout:
                break
            default:
                XCTFail("\(error)")
            }
        }
    }

    func testErrorWaiter() {
        let waiter = AWSClient.Waiter(
            acceptors: [
                .init(state: .retry, matcher: AWSErrorCodeMatcher("AccessDenied")),
                .init(state: .success, matcher: try! JMESPathMatcher("i", expected: 3)),
            ],
            minDelayTime: .seconds(2),
            command: self.operation
        )
        let input = Input()
        let response = Self.client.waitUntil(input, waiter: waiter, logger: TestEnvironment.logger)

        var i = 0
        XCTAssertNoThrow(try Self.awsServer.process { (_: Input) -> AWSTestServer.Result<Output> in
            i += 1
            if i < 3 {
                return .error(.accessDenied, continueProcessing: true)
            } else {
                return .result(Output(i: i), continueProcessing: false)
            }
        })

        XCTAssertNoThrow(try response.wait())
    }

    func testErrorStatusWaiter() {
        let waiter = AWSClient.Waiter(
            acceptors: [
                .init(state: .retry, matcher: AWSErrorStatusMatcher(404)),
                .init(state: .success, matcher: try! JMESPathMatcher("i", expected: 3)),
            ],
            minDelayTime: .seconds(2),
            command: self.operation
        )
        let input = Input()
        let response = Self.client.waitUntil(input, waiter: waiter, logger: TestEnvironment.logger)

        var i = 0
        XCTAssertNoThrow(try Self.awsServer.process { (_: Input) -> AWSTestServer.Result<Output> in
            i += 1
            if i < 3 {
                return .error(.notFound, continueProcessing: true)
            } else {
                return .result(Output(i: i), continueProcessing: false)
            }
        })

        XCTAssertNoThrow(try response.wait())
    }
}
