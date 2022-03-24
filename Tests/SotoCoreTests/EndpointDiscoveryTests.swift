//===----------------------------------------------------------------------===//
//
// This source file is part of the Soto for AWS open source project
//
// Copyright (c) 2017-2020 the Soto project authors
// Licensed under Apache License v2.0
//
// See LICENSE.txt for license information
// See CONTRIBUTORS.txt for the list of Soto project authors
//
// SPDX-License-Identifier: Apache-2.0
//
//===----------------------------------------------------------------------===//

import NIOCore
import SotoCore
import SotoTestUtils
#if compiler(>=5.6)
@preconcurrency import NIOConcurrencyHelpers
#else
import NIOConcurrencyHelpers
#endif
import XCTest

class EndpointDiscoveryTests: XCTestCase {
    final class Service: AWSService {
        let client: AWSClient
        let config: AWSServiceConfig
        let endpointStorage: AWSEndpointStorage
        let endpointToDiscover: String
        let getEndpointsCalledCount = NIOAtomic.makeAtomic(value: 0)

        required init(from: EndpointDiscoveryTests.Service, patch: AWSServiceConfig.Patch) {
            self.client = from.client
            self.config = from.config.with(patch: patch)
            self.endpointStorage = AWSEndpointStorage(endpoint: self.config.endpoint)
            self.endpointToDiscover = from.endpointToDiscover
            self.getEndpointsCalledCount.store(from.getEndpointsCalledCount.load())
        }

        /// init
        init(client: AWSClient, endpoint: String? = nil, endpointToDiscover: String = "", expectedCallCount: Int) {
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
        }

        struct TestRequest: AWSEncodableShape {}

        public func getEndpoints(logger: Logger, on eventLoop: EventLoop) -> EventLoopFuture<AWSEndpoints> {
            self.getEndpointsCalledCount.add(1)
            return eventLoop.scheduleTask(in: .milliseconds(200)) {
                return AWSEndpoints(endpoints: [.init(address: self.endpointToDiscover, cachePeriodInMinutes: 60)])
            }.futureResult
        }

        @discardableResult public func test(_ input: TestRequest, logger: Logger = AWSClient.loggingDisabled, on eventLoop: EventLoop? = nil) -> EventLoopFuture<Void> {
            return self.client.execute(
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
            self.getEndpointsCalledCount.add(1)
            return eventLoop.scheduleTask(in: .milliseconds(200)) {
                return AWSEndpoints(endpoints: [.init(address: self.endpointToDiscover, cachePeriodInMinutes: 0)])
            }.futureResult
        }

        @discardableResult public func testDontCache(logger: Logger = AWSClient.loggingDisabled, on eventLoop: EventLoop? = nil) -> EventLoopFuture<Void> {
            return self.client.execute(
                operation: "Test",
                path: "/test",
                httpMethod: .GET,
                serviceConfig: self.config,
                endpointDiscovery: .init(storage: self.endpointStorage, discover: self.getEndpointsDontCache, required: true),
                logger: logger,
                on: eventLoop
            )
        }

        @discardableResult public func testNotRequired(_ input: TestRequest, logger: Logger = AWSClient.loggingDisabled, on eventLoop: EventLoop? = nil) -> EventLoopFuture<Void> {
            return self.client.execute(
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
        let service = Service(client: client, endpointToDiscover: awsServer.address, expectedCallCount: 1).with(middlewares: TestEnvironment.middlewares)
        let response = service.test(.init(), logger: TestEnvironment.logger).flatMap { _ in
            service.test(.init(), logger: TestEnvironment.logger)
        }

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

        try response.wait()
        XCTAssertEqual(service.getEndpointsCalledCount.load(), 1)
    }

    func testConcurrentEndpointDiscovery() throws {
        let awsServer = AWSTestServer(serviceProtocol: .json)
        let client = AWSClient(credentialProvider: .empty, httpClientProvider: .createNew)
        defer {
            XCTAssertNoThrow(try client.syncShutdown())
            XCTAssertNoThrow(try awsServer.stop())
        }
        let service = Service(client: client, endpointToDiscover: awsServer.address, expectedCallCount: 1).with(middlewares: TestEnvironment.middlewares)
        let response1 = service.test(.init(), logger: TestEnvironment.logger)
        let response2 = service.test(.init(), logger: TestEnvironment.logger)

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

        _ = try response1.and(response2).wait()
        XCTAssertEqual(service.getEndpointsCalledCount.load(), 1)
    }

    func testDontCacheEndpoint() throws {
        let awsServer = AWSTestServer(serviceProtocol: .json)
        let client = AWSClient(credentialProvider: .empty, httpClientProvider: .createNew)
        defer {
            XCTAssertNoThrow(try client.syncShutdown())
            XCTAssertNoThrow(try awsServer.stop())
        }
        let service = Service(client: client, endpointToDiscover: awsServer.address, expectedCallCount: 2).with(middlewares: TestEnvironment.middlewares)
        let response = service.testDontCache(logger: TestEnvironment.logger).flatMap { _ in
            service.testDontCache(logger: TestEnvironment.logger)
        }

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

        try response.wait()
        XCTAssertEqual(service.getEndpointsCalledCount.load(), 2)
    }

    func testDisableEndpointDiscovery() throws {
        let awsServer = AWSTestServer(serviceProtocol: .json)
        let client = AWSClient(credentialProvider: .empty, httpClientProvider: .createNew)
        defer {
            XCTAssertNoThrow(try client.syncShutdown())
            XCTAssertNoThrow(try awsServer.stop())
        }
        let service = Service(client: client, endpoint: awsServer.address, expectedCallCount: 0)
            .with(middlewares: TestEnvironment.middlewares)
        let response = service.testNotRequired(.init(), logger: TestEnvironment.logger)

        try awsServer.processRaw { request in
            TestEnvironment.logger.info("\(request)")
            let response = AWSTestServer.Response(httpStatus: .ok, headers: [:], body: nil)
            return .result(response, continueProcessing: false)
        }

        try response.wait()
        XCTAssertEqual(service.getEndpointsCalledCount.load(), 0)
    }
}
