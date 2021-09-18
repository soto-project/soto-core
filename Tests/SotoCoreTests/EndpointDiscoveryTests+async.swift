//===----------------------------------------------------------------------===//
//
// This source file is part of the Soto for AWS open source project
//
// Copyright (c) 2021 the Soto project authors
// Licensed under Apache License v2.0
//
// See LICENSE.txt for license information
// See CONTRIBUTORS.txt for the list of Soto project authors
//
// SPDX-License-Identifier: Apache-2.0
//
//===----------------------------------------------------------------------===//

#if compiler(>=5.5)

import _NIOConcurrency
import NIO
import SotoCore
import SotoTestUtils
import XCTest

@available(macOS 12.0, iOS 15.0, watchOS 8.0, tvOS 15.0, *)
class EndpointDiscoveryAsyncTests: XCTestCase {
    class Service: AWSService {
        let client: AWSClient
        let config: AWSServiceConfig
        let endpointStorage: AWSEndpointStorage
        let endpointToDiscover: String
        var getEndpointsCalledCount: Int

        required init(from: EndpointDiscoveryAsyncTests.Service, patch: AWSServiceConfig.Patch) {
            self.client = from.client
            self.config = from.config.with(patch: patch)
            self.endpointStorage = AWSEndpointStorage(endpoint: self.config.endpoint)
            self.endpointToDiscover = from.endpointToDiscover
            self.getEndpointsCalledCount = from.getEndpointsCalledCount
        }

        /// init
        init(client: AWSClient, endpoint: String? = nil, endpointToDiscover: String = "") {
            self.client = client
            self.config = .init(
                region: .euwest1,
                partition: .aws,
                service: "Test",
                serviceProtocol: .restjson,
                apiVersion: "2021-08-08",
                endpoint: endpoint
            )
            self.endpointStorage = AWSEndpointStorage(endpoint: self.config.endpoint)
            self.endpointToDiscover = endpointToDiscover
            self.getEndpointsCalledCount = 0
        }

        struct TestRequest: AWSEncodableShape {}

        public func getEndpoints(logger: Logger, on eventLoop: EventLoop) -> EventLoopFuture<AWSEndpoints> {
            self.getEndpointsCalledCount += 1
            return eventLoop.scheduleTask(in: .milliseconds(200)) {
                return AWSEndpoints(endpoints: [.init(address: self.endpointToDiscover, cachePeriodInMinutes: 60)])
            }.futureResult
        }

        public func test(_ input: TestRequest, logger: Logger = AWSClient.loggingDisabled, on eventLoop: EventLoop? = nil) async throws {
            return try await self.client.execute(
                operation: "Test",
                path: "/test",
                httpMethod: .GET,
                serviceConfig: self.config,
                input: input,
                endpointDiscovery: .init(storage: self.endpointStorage, discover: self.getEndpoints, required: true),
                logger: logger,
                on: eventLoop
            )
        }

        public func getEndpointsDontCache(logger: Logger, on eventLoop: EventLoop) -> EventLoopFuture<AWSEndpoints> {
            self.getEndpointsCalledCount += 1
            return eventLoop.scheduleTask(in: .milliseconds(200)) {
                return AWSEndpoints(endpoints: [.init(address: self.endpointToDiscover, cachePeriodInMinutes: 0)])
            }.futureResult
        }

        public func testDontCache(logger: Logger = AWSClient.loggingDisabled, on eventLoop: EventLoop? = nil) async throws {
            return try await self.client.execute(
                operation: "Test",
                path: "/test",
                httpMethod: .GET,
                serviceConfig: self.config,
                endpointDiscovery: .init(storage: self.endpointStorage, discover: self.getEndpointsDontCache, required: true),
                logger: logger,
                on: eventLoop
            )
        }

        public func testNotRequired(_ input: TestRequest, logger: Logger = AWSClient.loggingDisabled, on eventLoop: EventLoop? = nil) async throws {
            return try await self.client.execute(
                operation: "Test",
                path: "/test",
                httpMethod: .GET,
                serviceConfig: self.config,
                input: input,
                endpointDiscovery: .init(storage: self.endpointStorage, discover: self.getEndpoints, required: false),
                logger: logger,
                on: eventLoop
            )
        }
    }

    func testCachingEndpointDiscovery() throws {
        let awsServer = AWSTestServer(serviceProtocol: .restjson)
        let client = AWSClient(credentialProvider: .empty, httpClientProvider: .createNew)
        defer {
            XCTAssertNoThrow(try client.syncShutdown())
            XCTAssertNoThrow(try awsServer.stop())
        }
        let service = Service(client: client, endpointToDiscover: awsServer.address).with(middlewares: TestEnvironment.middlewares)

        XCTRunAsyncAndBlock {
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
            XCTAssertEqual(service.getEndpointsCalledCount, 1)
        }
    }

    func testConcurrentEndpointDiscovery() throws {
        let awsServer = AWSTestServer(serviceProtocol: .json)
        let client = AWSClient(credentialProvider: .empty, httpClientProvider: .createNew)
        defer {
            XCTAssertNoThrow(try client.syncShutdown())
            XCTAssertNoThrow(try awsServer.stop())
        }
        let service = Service(client: client, endpointToDiscover: awsServer.address).with(middlewares: TestEnvironment.middlewares)

        XCTRunAsyncAndBlock {
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
            XCTAssertEqual(service.getEndpointsCalledCount, 1)
        }
    }

    func testDontCacheEndpoint() throws {
        let awsServer = AWSTestServer(serviceProtocol: .json)
        let client = AWSClient(credentialProvider: .empty, httpClientProvider: .createNew)
        defer {
            XCTAssertNoThrow(try client.syncShutdown())
            XCTAssertNoThrow(try awsServer.stop())
        }
        let service = Service(client: client, endpointToDiscover: awsServer.address).with(middlewares: TestEnvironment.middlewares)
        XCTRunAsyncAndBlock {
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
            XCTAssertEqual(service.getEndpointsCalledCount, 2)
        }
    }

    func testDisableEndpointDiscovery() throws {
        let awsServer = AWSTestServer(serviceProtocol: .json)
        let client = AWSClient(credentialProvider: .empty, httpClientProvider: .createNew)
        defer {
            XCTAssertNoThrow(try client.syncShutdown())
            XCTAssertNoThrow(try awsServer.stop())
        }
        let service = Service(client: client, endpoint: awsServer.address)
            .with(middlewares: TestEnvironment.middlewares)

        XCTRunAsyncAndBlock {
            async let response: () = service.testNotRequired(.init(), logger: TestEnvironment.logger)

            try awsServer.processRaw { request in
                TestEnvironment.logger.info("\(request)")
                let response = AWSTestServer.Response(httpStatus: .ok, headers: [:], body: nil)
                return .result(response, continueProcessing: false)
            }

            try await response
            XCTAssertEqual(service.getEndpointsCalledCount, 0)
        }
    }
}

#endif // compiler(>=5.5)
