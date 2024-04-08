//===----------------------------------------------------------------------===//
//
// This source file is part of the Soto for AWS open source project
//
// Copyright (c) 2021-2022 the Soto project authors
// Licensed under Apache License v2.0
//
// See LICENSE.txt for license information
// See CONTRIBUTORS.txt for the list of Soto project authors
//
// SPDX-License-Identifier: Apache-2.0
//
//===----------------------------------------------------------------------===//

import Atomics
import NIOCore
import SotoCore
import SotoTestUtils
import XCTest

final class EndpointDiscoveryTests: XCTestCase {
    final class Service: AWSService {
        let client: AWSClient
        let config: AWSServiceConfig
        let endpointStorage: AWSEndpointStorage
        let endpointToDiscover: String
        let getEndpointsCalledCount = ManagedAtomic(0)

        required init(from: EndpointDiscoveryTests.Service, patch: AWSServiceConfig.Patch) {
            self.client = from.client
            self.config = from.config.with(patch: patch)
            self.endpointToDiscover = from.endpointToDiscover
            self.getEndpointsCalledCount.store(
                from.getEndpointsCalledCount.load(ordering: .sequentiallyConsistent),
                ordering: .sequentiallyConsistent
            )
            self.endpointStorage = AWSEndpointStorage()
        }

        /// init
        init(client: AWSClient, endpoint: String? = nil, endpointToDiscover: String = "") {
            self.client = client
            self.config = .init(
                region: .euwest1,
                partition: .aws,
                serviceName: "Test",
                serviceIdentifier: "test",
                serviceProtocol: .restjson,
                apiVersion: "2021-08-08",
                endpoint: endpoint
            )
            self.endpointToDiscover = endpointToDiscover
            self.endpointStorage = AWSEndpointStorage()
        }

        struct TestRequest: AWSEncodableShape {}

        @Sendable public func getEndpoints(logger: Logger) async throws -> AWSEndpoints {
            self.getEndpointsCalledCount.wrappingIncrement(ordering: .sequentiallyConsistent)
            try await Task.sleep(nanoseconds: 200_000_000)
            return AWSEndpoints(endpoints: [.init(address: self.endpointToDiscover, cachePeriodInMinutes: 60)])
        }

        public func test(_ input: TestRequest, logger: Logger = AWSClient.loggingDisabled) async throws {
            return try await self.client.execute(
                operation: "Test",
                path: "/test",
                httpMethod: .GET,
                serviceConfig: self.config.with(
                    middleware: EndpointDiscoveryMiddleware(storage: self.endpointStorage, discover: self.getEndpoints, required: true)
                ),
                input: input,
                logger: logger
            )
        }

        @Sendable public func getEndpointsDontCache(logger: Logger) async throws -> AWSEndpoints {
            self.getEndpointsCalledCount.wrappingIncrement(ordering: .sequentiallyConsistent)
            try await Task.sleep(nanoseconds: 200_000_000)
            return AWSEndpoints(endpoints: [.init(address: self.endpointToDiscover, cachePeriodInMinutes: 0)])
        }

        public func testDontCache(logger: Logger = AWSClient.loggingDisabled) async throws {
            return try await self.client.execute(
                operation: "Test",
                path: "/test",
                httpMethod: .GET,
                serviceConfig: self.config.with(
                    middleware: EndpointDiscoveryMiddleware(storage: self.endpointStorage, discover: self.getEndpointsDontCache, required: true)
                ),
                logger: logger
            )
        }

        public func testNotRequired(_ input: TestRequest, logger: Logger = AWSClient.loggingDisabled) async throws {
            return try await self.client.execute(
                operation: "Test",
                path: "/test",
                httpMethod: .GET,
                serviceConfig: self.config.with(
                    middleware: EndpointDiscoveryMiddleware(storage: self.endpointStorage, discover: self.getEndpoints, required: false)
                ),
                input: input,
                logger: logger
            )
        }
    }

    func testCachingEndpointDiscovery() async throws {
        #if os(iOS) // iOS async tests are failing in GitHub CI at the moment
        guard ProcessInfo.processInfo.environment["CI"] == nil else { return }
        #endif
        let awsServer = AWSTestServer(serviceProtocol: .restjson)
        let client = AWSClient(credentialProvider: .empty)
        defer {
            XCTAssertNoThrow(try client.syncShutdown())
            XCTAssertNoThrow(try awsServer.stop())
        }
        let service = Service(client: client, endpointToDiscover: awsServer.address).with(middleware: TestEnvironment.middlewares)

        async let response1: () = service.test(.init(), logger: TestEnvironment.logger)
        try awsServer.processRaw { request in
            TestEnvironment.logger.info("\(request)")
            let response = AWSTestServer.Response(httpStatus: .ok, headers: [:], body: nil)
            return .result(response, continueProcessing: false)
        }
        try await response1
        async let response2: () = service.test(.init(), logger: TestEnvironment.logger)
        try awsServer.processRaw { request in
            TestEnvironment.logger.info("\(request)")
            let response = AWSTestServer.Response(httpStatus: .ok, headers: [:], body: nil)
            return .result(response, continueProcessing: false)
        }
        try await response2
        XCTAssertEqual(service.getEndpointsCalledCount.load(ordering: .sequentiallyConsistent), 1)
    }

    func testConcurrentEndpointDiscovery() async throws {
        #if os(iOS) // iOS async tests are failing in GitHub CI at the moment
        guard ProcessInfo.processInfo.environment["CI"] == nil else { return }
        #endif
        let awsServer = AWSTestServer(serviceProtocol: .json)
        let client = AWSClient(credentialProvider: .empty)
        defer {
            XCTAssertNoThrow(try client.syncShutdown())
            XCTAssertNoThrow(try awsServer.stop())
        }
        let service = Service(client: client, endpointToDiscover: awsServer.address).with(middleware: TestEnvironment.middlewares)

        async let response1: () = service.test(.init(), logger: TestEnvironment.logger)
        async let response2: () = service.test(.init(), logger: TestEnvironment.logger)

        var count = 0
        try awsServer.processRaw { request in
            TestEnvironment.logger.info("\(request)")
            let response = AWSTestServer.Response(httpStatus: .ok, headers: [:], body: nil)
            count += 1
            if count > 1 {
                return .result(response, continueProcessing: false)
            } else {
                return .result(response, continueProcessing: true)
            }
        }

        try await response1
        try await response2
        XCTAssertEqual(service.getEndpointsCalledCount.load(ordering: .sequentiallyConsistent), 1)
    }

    func testDontCacheEndpoint() async throws {
        #if os(iOS) // iOS async tests are failing in GitHub CI at the moment
        guard ProcessInfo.processInfo.environment["CI"] == nil else { return }
        #endif
        let awsServer = AWSTestServer(serviceProtocol: .json)
        let client = AWSClient(credentialProvider: .empty)
        defer {
            XCTAssertNoThrow(try client.syncShutdown())
            XCTAssertNoThrow(try awsServer.stop())
        }
        let service = Service(client: client, endpointToDiscover: awsServer.address).with(middleware: TestEnvironment.middlewares)

        async let response1: () = service.testDontCache(logger: TestEnvironment.logger)
        try awsServer.processRaw { request in
            TestEnvironment.logger.info("\(request)")
            let response = AWSTestServer.Response(httpStatus: .ok, headers: [:], body: nil)
            return .result(response, continueProcessing: false)
        }
        try await response1
        async let response2: () = service.testDontCache(logger: TestEnvironment.logger)
        try awsServer.processRaw { request in
            TestEnvironment.logger.info("\(request)")
            let response = AWSTestServer.Response(httpStatus: .ok, headers: [:], body: nil)
            return .result(response, continueProcessing: false)
        }
        try await response2
        XCTAssertEqual(service.getEndpointsCalledCount.load(ordering: .sequentiallyConsistent), 2)
    }

    func testDisableEndpointDiscovery() async throws {
        #if os(iOS) // iOS async tests are failing in GitHub CI at the moment
        guard ProcessInfo.processInfo.environment["CI"] == nil else { return }
        #endif
        let awsServer = AWSTestServer(serviceProtocol: .json)
        let client = AWSClient(credentialProvider: .empty)
        defer {
            XCTAssertNoThrow(try client.syncShutdown())
            XCTAssertNoThrow(try awsServer.stop())
        }
        let service = Service(client: client, endpoint: awsServer.address)
            .with(middleware: TestEnvironment.middlewares)

        async let response: () = service.testNotRequired(.init(), logger: TestEnvironment.logger)

        try awsServer.processRaw { request in
            TestEnvironment.logger.info("\(request)")
            let response = AWSTestServer.Response(httpStatus: .ok, headers: [:], body: nil)
            return .result(response, continueProcessing: false)
        }

        try await response
        XCTAssertEqual(service.getEndpointsCalledCount.load(ordering: .sequentiallyConsistent), 0)
    }
}
