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
import NIOCore
import SotoCore
import SotoTestUtils
import XCTest

class WaiterTests: XCTestCase {
    struct TestService: AWSService {
        var client: AWSClient
        var config: AWSServiceConfig

        init(client: AWSClient, config: AWSServiceConfig) {
            self.client = client
            self.config = config
        }

        init(from service: TestService, patch: AWSServiceConfig.Patch) {
            self.init(client: service.client, config: service.config.with(patch: patch))
        }

        struct Input: AWSEncodableShape & Decodable {}

        struct Output: AWSDecodableShape & Encodable {
            let i: Int
        }

        @Sendable func operation(input: Input, logger: Logger) async throws -> Output {
            try await self.client.execute(
                operation: "Basic",
                path: "/",
                httpMethod: .POST,
                serviceConfig: self.config,
                input: input,
                logger: logger
            )
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

        @Sendable func arrayOperation(input: Input, logger: Logger) async throws -> ArrayOutput {
            try await self.client.execute(
                operation: "Basic",
                path: "/",
                httpMethod: .POST,
                serviceConfig: self.config,
                input: input,
                logger: logger
            )
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

        @Sendable func optionalArrayOperation(input: Input, logger: Logger) async throws -> OptionalArrayOutput {
            try await self.client.execute(
                operation: "Basic",
                path: "/",
                httpMethod: .POST,
                serviceConfig: self.config,
                input: input,
                logger: logger
            )
        }
    }

    var awsServer: AWSTestServer!
    var config: AWSServiceConfig!
    var client: AWSClient!

    override func setUp() {
        self.awsServer = AWSTestServer(serviceProtocol: .json)
        self.config = createServiceConfig(serviceProtocol: .json(version: "1.1"), endpoint: self.awsServer.address)
        self.client = createAWSClient(credentialProvider: .empty, middlewares: AWSLoggingMiddleware())
    }

    override func tearDown() {
        XCTAssertNoThrow(try self.client.syncShutdown())
        XCTAssertNoThrow(try self.awsServer.stop())
    }

    func testJMESPathWaiter() async throws {
        let service = TestService(client: self.client, config: self.config)
        let waiter = AWSClient.Waiter(
            acceptors: [
                .init(state: .success, matcher: try! JMESPathMatcher("array[*].status", expected: [true, true, true])),
            ],
            minDelayTime: .milliseconds(2),
            command: service.arrayOperation
        )
        let input = TestService.Input()
        async let responseTask: Void = self.client.waitUntil(input, waiter: waiter, logger: TestEnvironment.logger)

        var i = 0
        XCTAssertNoThrow(try self.awsServer.process { (_: TestService.Input) -> AWSTestServer.Result<TestService.ArrayOutput> in
            i += 1
            return .result(TestService.ArrayOutput(array: [.init(i >= 3), .init(i >= 2), .init(i >= 1)]), continueProcessing: i < 3)
        })

        try await responseTask
    }

    func testJMESPathWaiterWithString() async throws {
        struct StringOutput: AWSDecodableShape & Encodable {
            let s: String
        }
        @Sendable func operation(input: TestService.Input, logger: Logger) async throws -> StringOutput {
            try await self.client.execute(operation: "Basic", path: "/", httpMethod: .POST, serviceConfig: self.config, input: input, logger: logger)
        }
        let waiter = AWSClient.Waiter(
            acceptors: [
                .init(state: .success, matcher: try! JMESPathMatcher("s", expected: "yes")),
            ],
            minDelayTime: .milliseconds(2),
            command: operation
        )
        let input = TestService.Input()
        async let responseTask: Void = self.client.waitUntil(input, waiter: waiter, logger: TestEnvironment.logger)

        var i = 0
        XCTAssertNoThrow(try self.awsServer.process { (_: TestService.Input) -> AWSTestServer.Result<StringOutput> in
            i += 1
            if i < 2 {
                return .result(.init(s: "no"), continueProcessing: true)
            } else {
                return .result(.init(s: "yes"), continueProcessing: false)
            }
        })

        try await responseTask
    }

    func testJMESPathWaiterWithEnum() async throws {
        enum YesNo: String, AWSDecodableShape & Encodable & CustomStringConvertible {
            case yes = "YES"
            case no = "NO"
            var description: String { return self.rawValue }
        }
        struct EnumOutput: AWSDecodableShape & Encodable {
            let e: YesNo
        }
        @Sendable func operation(input: TestService.Input, logger: Logger) async throws -> EnumOutput {
            try await self.client.execute(operation: "Basic", path: "/", httpMethod: .POST, serviceConfig: self.config, input: input, logger: logger)
        }
        let waiter = AWSClient.Waiter(
            acceptors: [
                .init(state: .success, matcher: try! JMESPathMatcher("e", expected: "YES")),
            ],
            minDelayTime: .milliseconds(2),
            command: operation
        )
        let input = TestService.Input()
        async let responseTask: Void = self.client.waitUntil(input, waiter: waiter, logger: TestEnvironment.logger)

        var i = 0
        XCTAssertNoThrow(try self.awsServer.process { (_: TestService.Input) -> AWSTestServer.Result<EnumOutput> in
            i += 1
            if i < 2 {
                return .result(.init(e: .no), continueProcessing: true)
            } else {
                return .result(.init(e: .yes), continueProcessing: false)
            }
        })

        try await responseTask
    }

    func testJMESAnyPathWaiter() async throws {
        let service = TestService(client: self.client, config: self.config)
        let waiter = AWSClient.Waiter(
            acceptors: [
                .init(state: .success, matcher: try! JMESAnyPathMatcher("array[*].status", expected: true)),
            ],
            minDelayTime: .milliseconds(2),
            command: service.arrayOperation
        )
        let input = TestService.Input()
        async let responseTask: Void = self.client.waitUntil(input, waiter: waiter, logger: TestEnvironment.logger)

        var i = 0
        XCTAssertNoThrow(try self.awsServer.process { (_: TestService.Input) -> AWSTestServer.Result<TestService.ArrayOutput> in
            i += 1
            if i < 2 {
                return .result(TestService.ArrayOutput(array: [false, false, false]), continueProcessing: true)
            } else {
                return .result(TestService.ArrayOutput(array: [false, true, false]), continueProcessing: false)
            }
        })

        try await responseTask
    }

    func testJMESAllPathWaiter() async throws {
        let service = TestService(client: self.client, config: self.config)
        let waiter = AWSClient.Waiter(
            acceptors: [
                .init(state: .success, matcher: try! JMESAllPathMatcher("array[*].status", expected: true)),
            ],
            minDelayTime: .milliseconds(2),
            command: service.arrayOperation
        )
        let input = TestService.Input()
        async let responseTask: Void = self.client.waitUntil(input, waiter: waiter, logger: TestEnvironment.logger)

        var i = 0
        XCTAssertNoThrow(try self.awsServer.process { (_: TestService.Input) -> AWSTestServer.Result<TestService.ArrayOutput> in
            i += 1
            if i < 2 {
                return .result(TestService.ArrayOutput(array: [false, true, false]), continueProcessing: true)
            } else {
                return .result(TestService.ArrayOutput(array: [true, true, true]), continueProcessing: false)
            }
        })

        try await responseTask
    }

    func testJMESPathPropertyValueWaiter() async throws {
        struct ArrayOutput: AWSDecodableShape & Encodable {
            @CustomCoding<StandardArrayCoder<Bool>> var array: [Bool]
        }
        struct Input: AWSEncodableShape & Decodable {
            let test: String
        }
        let awsServer = AWSTestServer(serviceProtocol: .xml)
        defer { XCTAssertNoThrow(try awsServer.stop()) }
        let config = createServiceConfig(serviceProtocol: .restxml, endpoint: awsServer.address)

        @Sendable func arrayOperation(input: Input, logger: Logger) async throws -> ArrayOutput {
            try await self.client.execute(operation: "Basic", path: "/", httpMethod: .POST, serviceConfig: config, input: input, logger: logger)
        }

        let waiter = AWSClient.Waiter(
            acceptors: [
                .init(state: .success, matcher: try! JMESPathMatcher("array[*]", expected: [true, true, true])),
            ],
            minDelayTime: .milliseconds(2),
            command: arrayOperation
        )
        let input = Input(test: "Input")
        async let responseTask: Void = self.client.waitUntil(input, waiter: waiter, logger: TestEnvironment.logger)

        var i = 0
        XCTAssertNoThrow(try awsServer.process { (_: Input) -> AWSTestServer.Result<ArrayOutput> in
            i += 1
            return .result(ArrayOutput(array: [.init(i >= 3), .init(i >= 2), .init(i >= 1)]), continueProcessing: i < 3)
        })

        try await responseTask
    }

    func testTimeoutWaiter() async throws {
        let service = TestService(client: self.client, config: self.config)
        let waiter = AWSClient.Waiter(
            acceptors: [
                .init(state: .success, matcher: try! JMESPathMatcher("i", expected: 3)),
            ],
            minDelayTime: .milliseconds(200),
            maxDelayTime: .milliseconds(400),
            command: service.operation
        )
        let input = TestService.Input()
        async let responseTask: Void = self.client.waitUntil(input, waiter: waiter, maxWaitTime: .milliseconds(400), logger: TestEnvironment.logger)

        var i = 0
        XCTAssertNoThrow(try self.awsServer.process { (_: TestService.Input) -> AWSTestServer.Result<TestService.Output> in
            i += 1
            return .result(TestService.Output(i: i), continueProcessing: i < 2)
        })

        do {
            try await responseTask
            XCTFail("Should not get here")
        } catch {
            XCTAssertEqual(error as? AWSClient.ClientError, .waiterTimeout)
        }
    }

    func testErrorWaiter() async throws {
        let service = TestService(client: self.client, config: self.config)
        let waiter = AWSClient.Waiter(
            acceptors: [
                .init(state: .retry, matcher: AWSErrorCodeMatcher("AccessDenied")),
                .init(state: .success, matcher: try! JMESPathMatcher("i", expected: 3)),
            ],
            minDelayTime: .milliseconds(2),
            command: service.operation
        )
        let input = TestService.Input()
        async let responseTask: Void = self.client.waitUntil(input, waiter: waiter, logger: TestEnvironment.logger)

        var i = 0
        XCTAssertNoThrow(try self.awsServer.process { (_: TestService.Input) -> AWSTestServer.Result<TestService.Output> in
            i += 1
            if i < 3 {
                return .error(.accessDenied, continueProcessing: true)
            } else {
                return .result(TestService.Output(i: i), continueProcessing: false)
            }
        })

        try await responseTask
    }

    func testErrorStatusWaiter() async throws {
        let service = TestService(client: self.client, config: self.config)
        let waiter = AWSClient.Waiter(
            acceptors: [
                .init(state: .retry, matcher: AWSErrorStatusMatcher(404)),
                .init(state: .success, matcher: try! JMESPathMatcher("i", expected: 3)),
            ],
            minDelayTime: .milliseconds(2),
            command: service.operation
        )
        let input = TestService.Input()
        async let responseTask: Void = self.client.waitUntil(input, waiter: waiter, logger: TestEnvironment.logger)

        var i = 0
        XCTAssertNoThrow(try self.awsServer.process { (_: TestService.Input) -> AWSTestServer.Result<TestService.Output> in
            i += 1
            if i < 3 {
                return .error(.notFound, continueProcessing: true)
            } else {
                return .result(TestService.Output(i: i), continueProcessing: false)
            }
        })

        try await responseTask
    }
}
