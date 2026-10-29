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

import Foundation
import HTTPTypes
import NIOCore
import SotoTestUtils
import Testing

@testable import SotoCore

struct AWSServiceTests {
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

    @Test func testRegion() async throws {
        let client = createAWSClient(credentialProvider: .empty)
        try await withClient(client) {
            let serviceConfig = createServiceConfig(region: .apnortheast2)
            let service = TestService(client: client, config: serviceConfig)
            #expect(service.region == .apnortheast2)
        }
    }

    @Test func testEndpoint() async throws {
        let client = createAWSClient(credentialProvider: .empty)
        try await withClient(client) {
            let serviceConfig = createServiceConfig(endpoint: "https://my-endpoint.com")
            let service = TestService(client: client, config: serviceConfig)
            #expect(service.endpoint == "https://my-endpoint.com")
        }
    }

    @Test func testPartitionEndpoint() async throws {
        let client = createAWSClient(credentialProvider: .empty)
        try await withClient(client) {
            let serviceConfig = createServiceConfig(
                serviceEndpoints: ["aws-global": "aws-global.com"],
                partitionEndpoints: [.aws: (endpoint: "aws-global", region: .uswest2)]
            )
            let service = TestService(client: client, config: serviceConfig)
            #expect(service.endpoint == "https://aws-global.com")
            #expect(service.region == .uswest2)
        }
    }

    @Test func testVariantEndpoint() async throws {
        let client = createAWSClient(credentialProvider: .empty)
        try await withClient(client) {
            let serviceConfig = createServiceConfig(
                region: .cacentral1,
                variantEndpoints: [.fips: .init(endpoints: ["ca-central-1": "my-service-fips.com"])],
                options: .useFipsEndpoint
            )
            let service = TestService(client: client, config: serviceConfig)
            #expect(service.endpoint == "https://my-service-fips.com")
        }
    }

    @Test func testVariantCallbackEndpoint() async throws {
        let client = createAWSClient(credentialProvider: .empty)
        try await withClient(client) {
            let serviceConfig = createServiceConfig(
                region: .euwest3,
                service: "my-service",
                variantEndpoints: [.fips: .init(defaultEndpoint: { region in "my-service-fips.\(region).aws.com" })],
                options: .useFipsEndpoint
            )
            let service = TestService(client: client, config: serviceConfig)
            #expect(service.endpoint == "https://my-service-fips.eu-west-3.aws.com")
        }
    }

    @Test func testVariantPartitionEndpoint() async throws {
        let client = createAWSClient(credentialProvider: .empty)
        try await withClient(client) {
            let serviceConfig = createServiceConfig(
                serviceEndpoints: ["aws-global": "aws-global.com"],
                partitionEndpoints: [.aws: (endpoint: "aws-global", region: .uswest2)],
                variantEndpoints: [.fips: .init(endpoints: ["aws-global": "aws-fips-global.com"])],
                options: .useFipsEndpoint
            )
            let service = TestService(client: client, config: serviceConfig)
            #expect(service.endpoint == "https://aws-fips-global.com")
            #expect(service.region == .uswest2)
        }
    }

    @Test func testWith() async throws {
        let client = createAWSClient(credentialProvider: .empty)
        try await withClient(client) {
            let serviceConfig = createServiceConfig()
            let service = TestService(client: client, config: serviceConfig)
            let service2 = service.with(timeout: .seconds(2048), options: .init(rawValue: 0x67FF))
            #expect(service2.config.timeout == .seconds(2048))
            #expect(service2.config.options == .init(rawValue: 0x67FF))
        }
    }

    @Test func testWithMiddleware() async throws {
        struct TestMiddleware: AWSMiddlewareProtocol {
            func handle(
                _ request: AWSHTTPRequest,
                context: AWSMiddlewareContext,
                next: (AWSHTTPRequest, AWSMiddlewareContext) async throws -> AWSHTTPResponse
            ) async throws -> AWSHTTPResponse {
                var request = request
                request.request.headerFields[values: HTTPField.Name("Test")!].append("testWithMiddleware")
                return try await next(request, context)
            }
        }
        let client = createAWSClient(credentialProvider: .empty)
        try await withClient(client) {
            let service = TestService(client: client, config: createServiceConfig())
            let service2 = service.with(middleware: TestMiddleware())
            let request = AWSHTTPRequest(request: HTTPRequest(method: .get, url: URL(string: "http://testurl.com")!), body: .init())
            let context = AWSMiddlewareContext(
                operation: "TestURL",
                serviceConfig: service2.config,
                credential: .empty,
                logger: TestEnvironment.logger
            )
            let response = try await service2.config.middleware!.handle(request, context: context) { request, _ in
                .init(response: HTTPResponse(status: .ok, headerFields: request.headers), body: request.body)
            }
            #expect(response.headers[HTTPField.Name("Test")!] == "testWithMiddleware")
        }
    }

    @Test func testWithRegion() async throws {
        let client = createAWSClient(credentialProvider: .empty)
        try await withClient(client) {
            let service = TestService(client: client, config: createServiceConfig(region: .apnortheast2))
            let service2 = TestService(client: client, config: createServiceConfig(region: .useast1)).with(region: .apnortheast2)
            #expect(service.region == service2.region)
            #expect(service.endpoint == service2.endpoint)
        }
    }

    @Test func testSignURL() async throws {
        let client = createAWSClient(credentialProvider: .static(accessKeyId: "foo", secretAccessKey: "bar"))
        try await withClient(client) {
            let serviceConfig = createServiceConfig()
            let service = TestService(client: client, config: serviceConfig)
            let url = URL(string: "https://test.amazonaws.com?test2=true&space=sp%20ace&percent=addi+tion")!
            let request = HTTPRequest(method: .get, url: url)
            let signedURL = try await service.signURL(request: request, expires: .seconds(15 * 60))
            // remove signed query params
            let query = try #require(signedURL.query)
            let queryItems =
                query
                .split(separator: "&")
                .compactMap {
                    guard !$0.hasPrefix("X-Amz") else { return nil }
                    return String($0)
                }
                .joined(separator: "&")
            #expect(queryItems == "percent=addi%2Btion&space=sp%20ace&test2=true")
        }
    }

    @Test func testSignHeaders() async throws {
        let client = createAWSClient(credentialProvider: .static(accessKeyId: "foo", secretAccessKey: "bar"))
        try await withClient(client) {
            let serviceConfig = createServiceConfig()
            let service = TestService(client: client, config: serviceConfig)
            let url = URL(string: "https://test.amazonaws.com?test2=true&space=sp%20ace&percent=addi+tion")!
            var request = HTTPRequest(method: .get, url: url, headerFields: [.contentType: "application/json"])
            try await service.signHeaders(
                request: &request,
                body: .init(string: "Test payload")
            )
            // remove signed query params
            #expect(request.headerFields[.authorization] != nil)
        }
    }

    @Suite(.serialized)
    struct EnvironmentVariables {
        @Test func testEnvironmentEndpoint() {
            Environment.set("http://localhost:4566", for: "AWS_ENDPOINT_URL")
            defer { Environment.unset(name: "AWS_ENDPOINT_URL") }

            let config = createServiceConfig()
            #expect(config.endpoint == "http://localhost:4566")
            Environment.set("http://localhost:1234", for: "AWS_ENDPOINT_URL")
            #expect(config.endpoint == "http://localhost:4566")
            #expect(config.with(region: .uswest2).endpoint == "http://localhost:1234")
        }

        @Test func testServiceEnvironmentEndpoint() {
            Environment.set("http://localhost:1234", for: "AWS_ENDPOINT_URL")
            Environment.set("http://localhost:4566", for: "AWS_ENDPOINT_URL_API_GATEWAY")
            defer {
                Environment.unset(name: "AWS_ENDPOINT_URL")
                Environment.unset(name: "AWS_ENDPOINT_URL_API_GATEWAY")
            }

            let config = createServiceConfig(sdkId: "API Gateway")
            #expect(config.endpoint == "http://localhost:4566")
            Environment.set("http://localhost:7890", for: "AWS_ENDPOINT_URL_API_GATEWAY")
            let updatedConfig = config.with(options: .useFipsEndpoint)
            #expect(updatedConfig.endpoint == "http://localhost:7890")
            Environment.unset(name: "AWS_ENDPOINT_URL_API_GATEWAY")
            #expect(updatedConfig.with(region: .uswest2).endpoint == "http://localhost:1234")
        }

        @Test func testExplicitEndpointOverridesEnvironment() {
            Environment.set("http://localhost:4566", for: "AWS_ENDPOINT_URL")
            Environment.set("http://localhost:1234", for: "AWS_ENDPOINT_URL_API_GATEWAY")
            defer {
                Environment.unset(name: "AWS_ENDPOINT_URL")
                Environment.unset(name: "AWS_ENDPOINT_URL_API_GATEWAY")
            }

            let config = createServiceConfig(sdkId: "API Gateway", endpoint: "https://my-endpoint.com")
            #expect(config.endpoint == "https://my-endpoint.com")
            #expect(config.with(region: .uswest2).endpoint == "https://my-endpoint.com")
        }
    }
}
