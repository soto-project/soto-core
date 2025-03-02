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

import SotoTestUtils
import XCTest

@testable import SotoCore

class AWSServiceTests: XCTestCase {
    struct TestService: AWSService {
        var client: AWSClient
        var config: AWSServiceConfig

        /// init
        init(client: AWSClient, config: AWSServiceConfig) {
            self.client = client
            self.config = config
        }

        /// patch init
        init(from: Self, patch: AWSServiceConfig.Patch) {
            self.client = from.client
            self.config = from.config.with(patch: patch)
        }
    }

    func testRegion() {
        let client = createAWSClient(credentialProvider: .empty)
        defer { XCTAssertNoThrow(try client.syncShutdown()) }
        let serviceConfig = createServiceConfig(region: .apnortheast2)
        let service = TestService(client: client, config: serviceConfig)
        XCTAssertEqual(service.region, .apnortheast2)
    }

    func testEndpoint() {
        let client = createAWSClient(credentialProvider: .empty)
        defer { XCTAssertNoThrow(try client.syncShutdown()) }
        let serviceConfig = createServiceConfig(endpoint: "https://my-endpoint.com")
        let service = TestService(client: client, config: serviceConfig)
        XCTAssertEqual(service.endpoint, "https://my-endpoint.com")
    }

    func testPartitionEndpoint() {
        let client = createAWSClient(credentialProvider: .empty)
        defer { XCTAssertNoThrow(try client.syncShutdown()) }
        let serviceConfig = createServiceConfig(
            serviceEndpoints: ["aws-global": "aws-global.com"],
            partitionEndpoints: [.aws: (endpoint: "aws-global", region: .uswest2)]
        )
        let service = TestService(client: client, config: serviceConfig)
        XCTAssertEqual(service.endpoint, "https://aws-global.com")
        XCTAssertEqual(service.region, .uswest2)
    }

    func testVariantEndpoint() {
        let client = createAWSClient(credentialProvider: .empty)
        defer { XCTAssertNoThrow(try client.syncShutdown()) }
        let serviceConfig = createServiceConfig(
            region: .cacentral1,
            variantEndpoints: [.fips: .init(endpoints: ["ca-central-1": "my-service-fips.com"])],
            options: .useFipsEndpoint
        )
        let service = TestService(client: client, config: serviceConfig)
        XCTAssertEqual(service.endpoint, "https://my-service-fips.com")
    }

    func testVariantCallbackEndpoint() {
        let client = createAWSClient(credentialProvider: .empty)
        defer { XCTAssertNoThrow(try client.syncShutdown()) }
        let serviceConfig = createServiceConfig(
            region: .euwest3,
            service: "my-service",
            variantEndpoints: [.fips: .init(defaultEndpoint: { region in "my-service-fips.\(region).aws.com" })],
            options: .useFipsEndpoint
        )
        let service = TestService(client: client, config: serviceConfig)
        XCTAssertEqual(service.endpoint, "https://my-service-fips.eu-west-3.aws.com")
    }

    func testVariantPartitionEndpoint() {
        let client = createAWSClient(credentialProvider: .empty)
        defer { XCTAssertNoThrow(try client.syncShutdown()) }
        let serviceConfig = createServiceConfig(
            serviceEndpoints: ["aws-global": "aws-global.com"],
            partitionEndpoints: [.aws: (endpoint: "aws-global", region: .uswest2)],
            variantEndpoints: [.fips: .init(endpoints: ["aws-global": "aws-fips-global.com"])],
            options: .useFipsEndpoint
        )
        let service = TestService(client: client, config: serviceConfig)
        XCTAssertEqual(service.endpoint, "https://aws-fips-global.com")
        XCTAssertEqual(service.region, .uswest2)
    }

    func testWith() {
        let client = createAWSClient(credentialProvider: .empty)
        defer { XCTAssertNoThrow(try client.syncShutdown()) }
        let serviceConfig = createServiceConfig()
        let service = TestService(client: client, config: serviceConfig)
        let service2 = service.with(timeout: .seconds(2048), options: .init(rawValue: 0x67FF))
        XCTAssertEqual(service2.config.timeout, .seconds(2048))
        XCTAssertEqual(service2.config.options, .init(rawValue: 0x67FF))
    }

    func testWithMiddleware() async throws {
        struct TestMiddleware: AWSMiddlewareProtocol {
            func handle(
                _ request: AWSHTTPRequest,
                context: AWSMiddlewareContext,
                next: (AWSHTTPRequest, AWSMiddlewareContext) async throws -> AWSHTTPResponse
            ) async throws -> AWSHTTPResponse {
                var request = request
                request.headers.add(name: "Test", value: "testWithMiddleware")
                return try await next(request, context)
            }
        }
        let client = createAWSClient(credentialProvider: .empty)
        defer { XCTAssertNoThrow(try client.syncShutdown()) }
        let service = TestService(client: client, config: createServiceConfig())
        let service2 = service.with(middleware: TestMiddleware())
        let request = AWSHTTPRequest(url: URL(string: "http://testurl.com")!, method: .GET, headers: [:], body: .init())
        let context = AWSMiddlewareContext(
            operation: "TestURL",
            serviceConfig: service2.config,
            credential: EmptyCredential().getStaticCredential(),
            logger: TestEnvironment.logger
        )
        let response = try await service2.config.middleware!.handle(request, context: context) { request, _ in
            .init(status: .ok, headers: request.headers, body: request.body)
        }
        XCTAssertEqual(response.headers["Test"].first, "testWithMiddleware")
    }

    func testWithRegion() {
        let client = createAWSClient(credentialProvider: .empty)
        defer { XCTAssertNoThrow(try client.syncShutdown()) }
        let service = TestService(client: client, config: createServiceConfig(region: .apnortheast2))
        let service2 = TestService(client: client, config: createServiceConfig(region: .useast1)).with(region: .apnortheast2)
        XCTAssertEqual(service.region, service2.region)
        XCTAssertEqual(service.endpoint, service2.endpoint)
    }

    func testSignURL() async throws {
        let client = createAWSClient(credentialProvider: .static(accessKeyId: "foo", secretAccessKey: "bar"))
        defer { XCTAssertNoThrow(try client.syncShutdown()) }
        let serviceConfig = createServiceConfig()
        let service = TestService(client: client, config: serviceConfig)
        let url = URL(string: "https://test.amazonaws.com?test2=true&space=sp%20ace&percent=addi+tion")!
        let signedURL = try await service.signURL(url: url, httpMethod: .GET, expires: .minutes(15))
        // remove signed query params
        let query = try XCTUnwrap(signedURL.query)
        let queryItems =
            query
            .split(separator: "&")
            .compactMap {
                guard !$0.hasPrefix("X-Amz") else { return nil }
                return String($0)
            }
            .joined(separator: "&")
        XCTAssertEqual(queryItems, "percent=addi%2Btion&space=sp%20ace&test2=true")
    }

    func testSignHeaders() async throws {
        let client = createAWSClient(credentialProvider: .static(accessKeyId: "foo", secretAccessKey: "bar"))
        defer { XCTAssertNoThrow(try client.syncShutdown()) }
        let serviceConfig = createServiceConfig()
        let service = TestService(client: client, config: serviceConfig)
        let url = URL(string: "https://test.amazonaws.com?test2=true&space=sp%20ace&percent=addi+tion")!
        let headers = try await service.signHeaders(
            url: url,
            httpMethod: .GET,
            headers: ["Content-Type": "application/json"],
            body: .init(string: "Test payload")
        )
        // remove signed query params
        XCTAssertNotNil(headers["Authorization"].first)
    }
}
