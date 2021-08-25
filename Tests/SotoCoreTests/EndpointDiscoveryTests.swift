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

import SotoCore
import SotoTestUtils
import XCTest

class EndpointDiscoveryTests: XCTestCase {
    
    class Service: AWSService {
        
        let client: AWSClient
        let config: AWSServiceConfig
        let endpointStorage: EndpointStorage
        let endpointToDiscover: String
        var getEndpointsCalledCount: Int
        
        required init(from: EndpointDiscoveryTests.Service, patch: AWSServiceConfig.Patch) {
            self.client = from.client
            self.config = from.config.with(patch: patch)
            self.endpointStorage = from.endpointStorage
            self.endpointToDiscover =  from.endpointToDiscover
            self.getEndpointsCalledCount = from.getEndpointsCalledCount
        }
        
        /// init
        init(client: AWSClient, endpoint: String) {
            self.client = client
            self.config = .init(
                region: .euwest1,
                partition: .aws,
                service: "Test",
                serviceProtocol: .restjson,
                apiVersion: "2021-08-08"
            )
            self.endpointStorage = EndpointStorage()
            self.endpointToDiscover = endpoint
            self.getEndpointsCalledCount = 0
        }
        
        struct TestRequest: AWSEncodableShape { }
        
        public func getEndpoints(logger: Logger, on eventLoop: EventLoop) -> EventLoopFuture<AWSEndpoints> {
            self.getEndpointsCalledCount += 1
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
                endpointDiscovery: .init(storage: self.endpointStorage, discover: getEndpoints, required: true),
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
        
        @discardableResult public func testDontCache(logger: Logger = AWSClient.loggingDisabled, on eventLoop: EventLoop? = nil) -> EventLoopFuture<Void> {
            return self.client.execute(
                operation: "Test",
                path: "/test",
                httpMethod: .GET,
                serviceConfig: self.config,
                endpointDiscovery: .init(storage: self.endpointStorage, discover: getEndpointsDontCache, required: true),
                logger: logger,
                on: eventLoop
            )
        }
    }
    
    func testCachingEndpointDiscovery() throws {
        let awsServer = AWSTestServer(serviceProtocol: .json)
        let client = AWSClient(httpClientProvider: .createNew)
        defer {
            XCTAssertNoThrow(try client.syncShutdown())
            XCTAssertNoThrow(try awsServer.stop())
        }
        let service = Service(client: client, endpoint: awsServer.address)
        let response = service.test(.init()).flatMap { _ in
            service.test(.init())
        }

        var count = 0
        try awsServer.processRaw { _ in
            let response = AWSTestServer.Response(httpStatus: .ok, headers: [:], body: nil)
            count += 1
            if count > 1 {
                return .result(response, continueProcessing: false)
            } else {
                return .result(response, continueProcessing: true)
            }
        }

        try response.wait()
        XCTAssertEqual(service.getEndpointsCalledCount, 1)
    }
    
    func testConcurrentEndpointDiscovery() throws {
        let awsServer = AWSTestServer(serviceProtocol: .json)
        let client = AWSClient(httpClientProvider: .createNew)
        defer {
            XCTAssertNoThrow(try client.syncShutdown())
            XCTAssertNoThrow(try awsServer.stop())
        }
        let service = Service(client: client, endpoint: awsServer.address)
        let response1 = service.test(.init())
        let response2 = service.test(.init())

        var count = 0
        try awsServer.processRaw { _ in
            let response = AWSTestServer.Response(httpStatus: .ok, headers: [:], body: nil)
            count += 1
            if count > 1 {
                return .result(response, continueProcessing: false)
            } else {
                return .result(response, continueProcessing: true)
            }
        }

        _ = try response1.and(response2).wait()
        XCTAssertEqual(service.getEndpointsCalledCount, 1)
    }
    
    func testDontCacheEndpoint() throws {
        let awsServer = AWSTestServer(serviceProtocol: .json)
        let client = AWSClient(httpClientProvider: .createNew)
        defer {
            XCTAssertNoThrow(try client.syncShutdown())
            XCTAssertNoThrow(try awsServer.stop())
        }
        let service = Service(client: client, endpoint: awsServer.address)
        let response = service.testDontCache().flatMap { _ in
            service.testDontCache()
        }

        var count = 0
        try awsServer.processRaw { _ in
            let response = AWSTestServer.Response(httpStatus: .ok, headers: [:], body: nil)
            count += 1
            if count > 1 {
                return .result(response, continueProcessing: false)
            } else {
                return .result(response, continueProcessing: true)
            }
        }

        try response.wait()
        XCTAssertEqual(service.getEndpointsCalledCount, 2)
    }
}
