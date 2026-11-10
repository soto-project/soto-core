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

import HTTPTypes
import Logging
import NIOCore
import SotoCore
import SotoTestUtils
import Synchronization
import Testing

struct WaiterTests {
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
                httpMethod: .post,
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
                httpMethod: .post,
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
                httpMethod: .post,
                serviceConfig: self.config,
                input: input,
                logger: logger
            )
        }
    }

    @Test func testJMESPathWaiter() async throws {
        let count = Atomic(0)
        let mockHTTPClient = MockHTTPClient { (input: TestService.Input) in
            let newCount = count.add(1, ordering: .relaxed).newValue
            return TestService.ArrayOutput(array: [.init(newCount >= 3), .init(newCount >= 2), .init(newCount >= 1)])
        }
        let client = AWSClient(credentialProvider: .empty, httpClient: mockHTTPClient)
        let service = TestService(client: client, config: createServiceConfig())
        try await withClient(client) {
            let waiter = AWSClient.Waiter(
                acceptors: [
                    .init(state: .success, matcher: try! JMESPathMatcher("array[*].status", expected: [true, true, true]))
                ],
                minDelayTime: .milliseconds(2),
                command: service.arrayOperation
            )
            let input = TestService.Input()
            try await service.client.waitUntil(input, waiter: waiter, logger: TestEnvironment.logger)
        }
    }

    @Test func testJMESPathWaiterWithString() async throws {
        struct StringOutput: AWSDecodableShape & Encodable {
            let s: String
        }
        let count = Atomic(0)
        let mockHTTPClient = MockHTTPClient { (input: TestService.Input) in
            let newCount = count.add(1, ordering: .relaxed).newValue
            if newCount < 2 {
                return StringOutput(s: "no")
            } else {
                return StringOutput(s: "yes")
            }
        }
        let client = AWSClient(credentialProvider: .empty, httpClient: mockHTTPClient)
        let service = TestService(client: client, config: createServiceConfig())
        @Sendable func operation(input: TestService.Input, logger: Logger) async throws -> StringOutput {
            try await service.client.execute(
                operation: "Basic",
                path: "/",
                httpMethod: .post,
                serviceConfig: service.config,
                input: input,
                logger: logger
            )
        }
        try await withClient(client) {
            let waiter = AWSClient.Waiter(
                acceptors: [
                    .init(state: .success, matcher: try! JMESPathMatcher("s", expected: "yes"))
                ],
                minDelayTime: .milliseconds(2),
                command: operation
            )
            let input = TestService.Input()
            try await service.client.waitUntil(input, waiter: waiter, logger: TestEnvironment.logger)
        }
    }

    @Test func testJMESPathWaiterWithRawRepresentable() async throws {
        struct YesNo: RawRepresentable, Sendable, Codable {
            let rawValue: Int

            static var yes: Self { .init(rawValue: 1) }
            static var no: Self { .init(rawValue: 0) }
        }
        struct EnumOutput: AWSDecodableShape & Encodable {
            let e: YesNo
        }
        let count = Atomic(0)
        let mockHTTPClient = MockHTTPClient { (input: TestService.Input) in
            let newCount = count.add(1, ordering: .relaxed).newValue
            if newCount < 2 {
                return EnumOutput(e: .no)
            } else {
                return EnumOutput(e: .yes)
            }
        }
        let client = AWSClient(credentialProvider: .empty, httpClient: mockHTTPClient)
        let service = TestService(client: client, config: createServiceConfig())
        @Sendable func operation(input: TestService.Input, logger: Logger) async throws -> EnumOutput {
            try await service.client.execute(
                operation: "Basic",
                path: "/",
                httpMethod: .post,
                serviceConfig: service.config,
                input: input,
                logger: logger
            )
        }
        try await withClient(client) {
            let waiter = AWSClient.Waiter(
                acceptors: [
                    .init(state: .success, matcher: try! JMESPathMatcher("e", expected: 1))
                ],
                minDelayTime: .milliseconds(2),
                command: operation
            )
            let input = TestService.Input()
            try await service.client.waitUntil(input, waiter: waiter, logger: TestEnvironment.logger)
        }
    }

    @Test func testJMESAnyPathWaiter() async throws {
        let count = Atomic(0)
        let mockHTTPClient = MockHTTPClient { (input: TestService.Input) in
            let newCount = count.add(1, ordering: .relaxed).newValue
            if newCount < 2 {
                return TestService.ArrayOutput(array: [false, false, false])
            } else {
                return TestService.ArrayOutput(array: [false, true, false])
            }
        }
        let client = AWSClient(credentialProvider: .empty, httpClient: mockHTTPClient)
        let service = TestService(client: client, config: createServiceConfig())
        try await withClient(client) {
            let waiter = AWSClient.Waiter(
                acceptors: [
                    .init(state: .success, matcher: try! JMESAnyPathMatcher("array[*].status", expected: true))
                ],
                minDelayTime: .milliseconds(2),
                command: service.arrayOperation
            )
            let input = TestService.Input()
            try await service.client.waitUntil(input, waiter: waiter, logger: TestEnvironment.logger)
        }
    }

    @Test func testJMESAllPathWaiter() async throws {
        let count = Atomic(0)
        let mockHTTPClient = MockHTTPClient { (input: TestService.Input) in
            let newCount = count.add(1, ordering: .relaxed).newValue
            if newCount < 2 {
                return TestService.ArrayOutput(array: [false, true, false])
            } else {
                return TestService.ArrayOutput(array: [true, true, true])
            }
        }
        let client = AWSClient(credentialProvider: .empty, httpClient: mockHTTPClient)
        let service = TestService(client: client, config: createServiceConfig())
        try await withClient(client) {
            let waiter = AWSClient.Waiter(
                acceptors: [
                    .init(state: .success, matcher: try! JMESAllPathMatcher("array[*].status", expected: true))
                ],
                minDelayTime: .milliseconds(2),
                command: service.arrayOperation
            )
            let input = TestService.Input()
            try await service.client.waitUntil(input, waiter: waiter, logger: TestEnvironment.logger)
        }
    }

    @Test func testJMESPathPropertyValueWaiter() async throws {
        struct ArrayOutput: AWSDecodableShape & Encodable {
            @CustomCoding<StandardArrayCoder<Bool>> var array: [Bool]
        }
        struct Input: AWSEncodableShape & Decodable {
            let test: String
        }
        let count = Atomic(0)
        let mockHTTPClient = MockHTTPClient(serviceProtocol: .restxml) { (input: Input) in
            let newCount = count.add(1, ordering: .relaxed).newValue
            return ArrayOutput(array: [.init(newCount >= 3), .init(newCount >= 2), .init(newCount >= 1)])
        }
        let client = AWSClient(credentialProvider: .empty, httpClient: mockHTTPClient)
        let serviceConfig = createServiceConfig(serviceProtocol: .restxml)
        let service = TestService(client: client, config: serviceConfig)

        @Sendable func arrayOperation(input: Input, logger: Logger) async throws -> ArrayOutput {
            try await service.client.execute(
                operation: "Basic",
                path: "/",
                httpMethod: .post,
                serviceConfig: serviceConfig,
                input: input,
                logger: logger
            )
        }

        try await withClient(client) {
            let waiter = AWSClient.Waiter(
                acceptors: [
                    .init(state: .success, matcher: try! JMESPathMatcher("array[*]", expected: [true, true, true]))
                ],
                minDelayTime: .milliseconds(2),
                command: arrayOperation
            )
            let input = Input(test: "Input")
            try await service.client.waitUntil(input, waiter: waiter, logger: TestEnvironment.logger)
        }
    }

    @Test func testTimeoutWaiter() async throws {
        let count = Atomic(0)
        let mockHTTPClient = MockHTTPClient { (input: TestService.Input) in
            let newCount = count.add(1, ordering: .relaxed).newValue
            return TestService.Output(i: newCount)
        }
        let client = AWSClient(credentialProvider: .empty, httpClient: mockHTTPClient)
        let service = TestService(client: client, config: createServiceConfig())
        try await withClient(client) {
            let waiter = AWSClient.Waiter(
                acceptors: [
                    .init(state: .success, matcher: try! JMESPathMatcher("i", expected: 3))
                ],
                minDelayTime: .milliseconds(200),
                maxDelayTime: .milliseconds(400),
                command: service.operation
            )
            let error = await #expect(throws: AWSClient.ClientError.self) {
                try await service.client.waitUntil(
                    TestService.Input(),
                    waiter: waiter,
                    maxWaitTime: .milliseconds(400),
                    logger: TestEnvironment.logger
                )
            }
            #expect(error == .waiterTimeout)
        }
    }

    @Test func testErrorWaiter() async throws {
        let count = Atomic(0)
        let mockHTTPClient = MockHTTPClient { (input: TestService.Input) in
            let newCount = count.add(1, ordering: .relaxed).newValue
            if newCount < 3 {
                throw MockHTTPClient.AWSError(status: .unauthorized, code: "AccessDenied")
            } else {
                return TestService.Output(i: newCount)
            }
        }
        let client = AWSClient(credentialProvider: .empty, httpClient: mockHTTPClient)
        let service = TestService(client: client, config: createServiceConfig())
        try await withClient(client) {
            let waiter = AWSClient.Waiter(
                acceptors: [
                    .init(state: .retry, matcher: AWSErrorCodeMatcher("AccessDenied")),
                    .init(state: .success, matcher: try! JMESPathMatcher("i", expected: 3)),
                ],
                minDelayTime: .milliseconds(2),
                command: service.operation
            )
            try await service.client.waitUntil(TestService.Input(), waiter: waiter, logger: TestEnvironment.logger)
        }
    }

    @Test func testErrorStatusWaiter() async throws {
        let count = Atomic(0)
        let mockHTTPClient = MockHTTPClient { (input: TestService.Input) in
            let newCount = count.add(1, ordering: .relaxed).newValue
            if newCount < 3 {
                throw MockHTTPClient.AWSError(status: .notFound)
            } else {
                return TestService.Output(i: newCount)
            }
        }
        let client = AWSClient(credentialProvider: .empty, httpClient: mockHTTPClient)
        let service = TestService(client: client, config: createServiceConfig())
        try await withClient(client) {
            let waiter = AWSClient.Waiter(
                acceptors: [
                    .init(state: .retry, matcher: AWSErrorStatusMatcher(404)),
                    .init(state: .success, matcher: try! JMESPathMatcher("i", expected: 3)),
                ],
                minDelayTime: .milliseconds(2),
                command: service.operation
            )
            try await service.client.waitUntil(.init(), waiter: waiter, logger: TestEnvironment.logger)
        }
    }
}
