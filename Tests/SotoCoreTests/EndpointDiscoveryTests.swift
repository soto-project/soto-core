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

import Foundation
import HTTPTypes
import Logging
import NIOCore
import NIOHTTP1
import SotoCore
import SotoTestUtils
import Synchronization
import Testing

struct EndpointDiscoveryTests {
    final class Service: AWSService {
        let client: AWSClient
        let config: AWSServiceConfig
        let endpointStorage: AWSEndpointStorage

        required init(from: EndpointDiscoveryTests.Service, patch: AWSServiceConfig.Patch) {
            self.client = from.client
            self.config = from.config.with(patch: patch)
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
            self.endpointStorage = AWSEndpointStorage()
        }

        struct Endpoints: AWSDecodableShape & AWSEncodableShape {
            struct Endpoint: AWSDecodableShape & AWSEncodableShape {
                /// IP address of the endpoint.
                public let address: String
                /// Endpoint cache time to live (TTL) value.
                public let cachePeriodInMinutes: Int64
            }
            let endpoints: [Endpoint]
        }
        struct TestRequest: AWSEncodableShape {}

        @Sendable public func describeEndpoints(logger: Logger) async throws -> Endpoints {
            try await self.client.execute(
                operation: "DescribeEndpoints",
                path: "/endpoint",
                httpMethod: .get,
                serviceConfig: self.config,
                logger: logger
            )
        }

        func getEndpoints(logger: Logger) async throws -> AWSEndpoints {
            let response = try await self.describeEndpoints(logger: logger)
            return .init(
                endpoints: response.endpoints.map {
                    .init(address: "https://\($0.address)", cachePeriodInMinutes: $0.cachePeriodInMinutes)
                }
            )
        }

        public func test(_ input: TestRequest, logger: Logger = AWSClient.loggingDisabled) async throws {
            try await self.client.execute(
                operation: "Test",
                path: "/test",
                httpMethod: .get,
                serviceConfig: self.config.with(
                    middleware: EndpointDiscoveryMiddleware(storage: self.endpointStorage, discover: self.getEndpoints, required: true)
                ),
                input: input,
                logger: logger
            )
        }

        public func testNotRequired(_ input: TestRequest, logger: Logger = AWSClient.loggingDisabled) async throws {
            try await self.client.execute(
                operation: "TestNotRequired",
                path: "/testNotRequired",
                httpMethod: .get,
                serviceConfig: self.config.with(
                    middleware: EndpointDiscoveryMiddleware(storage: self.endpointStorage, discover: self.getEndpoints, required: false)
                ),
                input: input,
                logger: logger
            )
        }
    }

    @Test func testCachingEndpointDiscovery() async throws {
        let endpoint = "api.localhost:8090"
        let endpointCalledCount = Atomic(0)
        let httpClient = MockAWSHTTPClient { request in
            switch request.request.path {
            case "/test":
                #expect(request.request.authority == "api.localhost:8090")
                return .init(response: .init(status: .ok))
            case "/endpoint":
                endpointCalledCount.add(1, ordering: .relaxed)
                try await Task.sleep(nanoseconds: 200_000_000)
                let endpoints = Service.Endpoints(endpoints: [
                    .init(address: endpoint, cachePeriodInMinutes: 60)
                ])
                let json = try JSONEncoder().encode(endpoints)
                return .init(response: .init(status: .ok), body: .init(bytes: json))
            default:
                return .init(response: .init(status: .notFound))
            }
        }
        let client = AWSClient(credentialProvider: .empty, httpClient: httpClient)
        defer {
            #expect(throws: Never.self) { try client.syncShutdown() }
        }
        let service = Service(client: client).with(middleware: TestEnvironment.middlewares)

        _ = try await service.test(.init(), logger: TestEnvironment.logger)
        _ = try await service.test(.init(), logger: TestEnvironment.logger)
        #expect(endpointCalledCount.load(ordering: .relaxed) == 1)
    }

    @Test func testConcurrentEndpointDiscovery() async throws {
        let endpoint = "api.localhost:8090"
        let endpointCalledCount = Atomic(0)
        let httpClient = MockAWSHTTPClient { request in
            switch request.request.path {
            case "/test":
                #expect(request.request.authority == "api.localhost:8090")
                return .init(response: .init(status: .ok))
            case "/endpoint":
                endpointCalledCount.add(1, ordering: .relaxed)
                try await Task.sleep(nanoseconds: 200_000_000)
                let endpoints = Service.Endpoints(endpoints: [
                    .init(address: endpoint, cachePeriodInMinutes: 60)
                ])
                let json = try JSONEncoder().encode(endpoints)
                return .init(response: .init(status: .ok), body: .init(bytes: json))
            default:
                return .init(response: .init(status: .notFound))
            }
        }
        let client = AWSClient(credentialProvider: .empty, httpClient: httpClient)
        defer {
            #expect(throws: Never.self) { try client.syncShutdown() }
        }
        let service = Service(client: client).with(middleware: TestEnvironment.middlewares)

        async let response1 = service.test(.init(), logger: TestEnvironment.logger)
        async let response2 = service.test(.init(), logger: TestEnvironment.logger)

        try await response1
        try await response2
        #expect(endpointCalledCount.load(ordering: .relaxed) == 1)
    }

    @Test func testDontCacheEndpoint() async throws {
        let endpoint = "api.localhost:8090"
        let endpointCalledCount = Atomic(0)
        let httpClient = MockAWSHTTPClient { request in
            switch request.request.path {
            case "/test":
                #expect(request.request.authority == "api.localhost:8090")
                return .init(response: .init(status: .ok))
            case "/endpoint":
                endpointCalledCount.add(1, ordering: .relaxed)
                try await Task.sleep(nanoseconds: 200_000_000)
                let endpoints = Service.Endpoints(endpoints: [
                    .init(address: endpoint, cachePeriodInMinutes: 0)
                ])
                let json = try JSONEncoder().encode(endpoints)
                return .init(response: .init(status: .ok), body: .init(bytes: json))
            default:
                return .init(response: .init(status: .notFound))
            }
        }
        let client = AWSClient(credentialProvider: .empty, httpClient: httpClient)
        defer {
            #expect(throws: Never.self) { try client.syncShutdown() }
        }
        let service = Service(client: client).with(middleware: TestEnvironment.middlewares)

        _ = try await service.test(.init(), logger: TestEnvironment.logger)
        _ = try await service.test(.init(), logger: TestEnvironment.logger)
        #expect(endpointCalledCount.load(ordering: .relaxed) == 2)
    }

    @Test func testNotRequiredEndpointDiscovery() async throws {
        let endpoint = "api.localhost:8090"
        let httpClient = MockAWSHTTPClient { request in
            switch request.request.path {
            case "/testNotRequired":
                #expect(request.request.authority != "api.localhost:8090")
                return .init(response: .init(status: .ok))
            case "/endpoint":
                try await Task.sleep(for: .milliseconds(200))
                let endpoints = Service.Endpoints(endpoints: [
                    .init(address: endpoint, cachePeriodInMinutes: 60)
                ])
                let json = try JSONEncoder().encode(endpoints)
                return .init(response: .init(status: .ok), body: .init(bytes: json))
            default:
                return .init(response: .init(status: .notFound))
            }
        }
        let client = AWSClient(credentialProvider: .empty, httpClient: httpClient)
        defer {
            #expect(throws: Never.self) { try client.syncShutdown() }
        }
        let service = Service(client: client).with(middleware: TestEnvironment.middlewares)

        _ = try await service.testNotRequired(.init(), logger: TestEnvironment.logger)
    }
}
