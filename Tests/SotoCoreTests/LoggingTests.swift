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

import InMemoryLogging
import Logging
import NIOConcurrencyHelpers
import SotoTestUtils
import XCTest

@testable import SotoCore

class LoggingTests: XCTestCase {
    func testRequestIdIncrements() async throws {
        let inMemoryLogging = InMemoryLogHandler()
        var logger = Logger(label: "LoggingTests", factory: { _ in inMemoryLogging })
        logger.logLevel = .trace
        let server = AWSTestServer(serviceProtocol: .json)
        defer { XCTAssertNoThrow(try server.stop()) }
        let client = AWSClient(
            credentialProvider: .static(accessKeyId: "foo", secretAccessKey: "bar"),
            logger: logger
        )
        defer { XCTAssertNoThrow(try client.syncShutdown()) }
        let config = createServiceConfig(
            serviceProtocol: .json(version: "1.1"),
            endpoint: server.address
        )

        async let responseTask: Void = client.execute(operation: "test1", path: "/", httpMethod: .GET, serviceConfig: config, logger: logger)
        async let response2Task: Void = client.execute(operation: "test2", path: "/", httpMethod: .GET, serviceConfig: config, logger: logger)

        var count = 0
        XCTAssertNoThrow(
            try server.processRaw { _ in
                let results: [AWSTestServer.Result<AWSTestServer.Response>] = [
                    .result(.ok, continueProcessing: true),
                    .result(.ok, continueProcessing: false),
                ]
                let result = results[count]
                count += 1
                return result
            }
        )

        try await responseTask
        try await response2Task
        let requestId1 = inMemoryLogging.entries.first { $0.metadata["aws-operation"] == "test1" }?.metadata["aws-request-id"]
        let requestId2 = inMemoryLogging.entries.first { $0.metadata["aws-operation"] == "test2" }?.metadata["aws-request-id"]
        XCTAssertNotNil(requestId1)
        XCTAssertNotNil(requestId2)
        XCTAssertNotEqual(requestId1, requestId2)
    }

    func testAWSRequestResponse() async throws {
        let inMemoryLogging = InMemoryLogHandler()
        var logger = Logger(label: "LoggingTests", factory: { _ in inMemoryLogging })
        logger.logLevel = .trace
        let traceLogger = logger
        let server = AWSTestServer(serviceProtocol: .json)
        defer { XCTAssertNoThrow(try server.stop()) }
        let client = AWSClient(
            credentialProvider: .static(accessKeyId: "foo", secretAccessKey: "bar"),
            logger: logger
        )
        defer { XCTAssertNoThrow(try client.syncShutdown()) }
        let config = createServiceConfig(
            service: "test-service",
            serviceProtocol: .json(version: "1.1"),
            endpoint: server.address
        )

        async let responseTask: Void = client.execute(
            operation: "TestOperation",
            path: "/",
            httpMethod: .GET,
            serviceConfig: config,
            logger: traceLogger
        )

        XCTAssertNoThrow(
            try server.processRaw { _ in
                .result(.ok, continueProcessing: false)
            }
        )

        try await responseTask
        let requestEntry = inMemoryLogging.entries.first(where: { $0.message == "AWS Request" })
        XCTAssertNotNil(requestEntry)
        XCTAssertEqual(requestEntry?.level, .debug)
        XCTAssertEqual(requestEntry?.metadata["aws-operation"], "TestOperation")
        XCTAssertEqual(requestEntry?.metadata["aws-service"], "test-service")
        let responseEntry = inMemoryLogging.entries.first { $0.message == "AWS Response" }
        XCTAssertNotNil(responseEntry)
        XCTAssertEqual(responseEntry?.level, .trace)
        XCTAssertEqual(responseEntry?.metadata["aws-operation"], "TestOperation")
        XCTAssertEqual(responseEntry?.metadata["aws-service"], "test-service")
    }

    func testAWSError() async throws {
        let inMemoryLogging = InMemoryLogHandler()
        var logger = Logger(label: "LoggingTests", factory: { _ in inMemoryLogging })
        logger.logLevel = .trace
        let server = AWSTestServer(serviceProtocol: .json)
        defer { XCTAssertNoThrow(try server.stop()) }
        let client = AWSClient(
            credentialProvider: .static(accessKeyId: "foo", secretAccessKey: "bar"),
            options: .init(requestLogLevel: .debug, errorLogLevel: .info),
            logger: logger
        )
        defer { XCTAssertNoThrow(try client.syncShutdown()) }
        let config = createServiceConfig(
            serviceProtocol: .json(version: "1.1"),
            endpoint: server.address
        )

        async let responseTask: Void = client.execute(operation: "test", path: "/", httpMethod: .GET, serviceConfig: config, logger: logger)

        XCTAssertNoThrow(
            try server.processRaw { _ in
                .error(.accessDenied, continueProcessing: false)
            }
        )

        try? await responseTask
        XCTAssertEqual(inMemoryLogging.entries.first { $0.metadata["aws-error-code"] == "AccessDenied" }?.message, "AWS Error")
        XCTAssertEqual(inMemoryLogging.entries.first { $0.metadata["aws-error-code"] == "AccessDenied" }?.level, .info)
    }

    func testRetryRequest() async throws {
        let inMemoryLogging = InMemoryLogHandler()
        var logger = Logger(label: "LoggingTests", factory: { _ in inMemoryLogging })
        logger.logLevel = .trace
        let server = AWSTestServer(serviceProtocol: .json)
        defer { XCTAssertNoThrow(try server.stop()) }
        let client = AWSClient(
            credentialProvider: .static(accessKeyId: "foo", secretAccessKey: "bar"),
            logger: logger
        )
        defer { XCTAssertNoThrow(try client.syncShutdown()) }
        let config = createServiceConfig(
            serviceProtocol: .json(version: "1.1"),
            endpoint: server.address
        )

        async let responseTask: Void = client.execute(operation: "test1", path: "/", httpMethod: .GET, serviceConfig: config, logger: logger)

        var count = 0
        XCTAssertNoThrow(
            try server.processRaw { _ in
                let results: [AWSTestServer.Result<AWSTestServer.Response>] = [
                    .error(.internal, continueProcessing: true),
                    .result(.ok, continueProcessing: false),
                ]
                let result = results[count]
                count += 1
                return result
            }
        )

        try await responseTask
        XCTAssertEqual(inMemoryLogging.entries.first { $0.metadata["aws-retry-time"] != nil }?.message, "Retrying request")
        XCTAssertEqual(inMemoryLogging.entries.first { $0.metadata["aws-retry-time"] != nil }?.level, .trace)
    }

    func testNoCredentialProvider() async throws {
        let inMemoryLogging = InMemoryLogHandler()
        var logger = Logger(label: "LoggingTests", factory: { _ in inMemoryLogging })
        logger.logLevel = .trace
        let client = createAWSClient(credentialProvider: .selector(.custom { _ in NullCredentialProvider() }))
        defer { XCTAssertNoThrow(try client.syncShutdown()) }
        let serviceConfig = createServiceConfig()
        do {
            try await client.execute(
                operation: "Test",
                path: "/",
                httpMethod: .GET,
                serviceConfig: serviceConfig,
                logger: logger
            )
        } catch {}
        XCTAssertNotNil(inMemoryLogging.entries.first { $0.metadata["aws-error-message"] != "No credential provider found." })
    }

    func testRequestLogLevel() async throws {
        let inMemoryLogging = InMemoryLogHandler()
        var logger = Logger(label: "LoggingTests", factory: { _ in inMemoryLogging })
        logger.logLevel = .trace
        let traceLogger = logger
        let server = AWSTestServer(serviceProtocol: .json)
        defer { XCTAssertNoThrow(try server.stop()) }
        let client = AWSClient(
            credentialProvider: .static(accessKeyId: "foo", secretAccessKey: "bar"),
            options: .init(requestLogLevel: .trace),
            logger: logger
        )
        defer { XCTAssertNoThrow(try client.syncShutdown()) }
        let config = createServiceConfig(
            service: "test-service",
            serviceProtocol: .json(version: "1.1"),
            endpoint: server.address
        )

        async let responseTask: Void = client.execute(
            operation: "TestOperation",
            path: "/",
            httpMethod: .GET,
            serviceConfig: config,
            logger: traceLogger
        )

        XCTAssertNoThrow(
            try server.processRaw { _ in
                .result(.ok, continueProcessing: false)
            }
        )

        try await responseTask
        let requestEntry = try XCTUnwrap(inMemoryLogging.entries.first { $0.message == "AWS Request" })
        XCTAssertEqual(requestEntry.level, .trace)
    }

    func testLoggingMiddleware() async throws {
        struct Output: AWSDecodableShape & Encodable {
            let s: String
        }
        let inMemoryLogging = InMemoryLogHandler()
        var logger = Logger(label: "LoggingTests", factory: { _ in inMemoryLogging })
        logger.logLevel = .trace
        let traceLogger = logger
        let server = AWSTestServer(serviceProtocol: .json)
        defer { XCTAssertNoThrow(try server.stop()) }
        let client = AWSClient(
            credentialProvider: .static(accessKeyId: "foo", secretAccessKey: "bar"),
            middleware: AWSLoggingMiddleware(logger: logger, logLevel: .info),
            logger: logger
        )
        defer { XCTAssertNoThrow(try client.syncShutdown()) }
        let config = createServiceConfig(
            service: "test-service",
            serviceProtocol: .json(version: "1.1"),
            endpoint: server.address
        )

        async let responseTask: Output = client.execute(
            operation: "TestOperation",
            path: "/",
            httpMethod: .GET,
            serviceConfig: config,
            logger: traceLogger
        )

        XCTAssertNoThrow(
            try server.processRaw { _ in
                let output = Output(s: "TestOutputString")
                let byteBuffer = try JSONEncoder().encodeAsByteBuffer(output, allocator: ByteBufferAllocator())
                let response = AWSTestServer.Response(httpStatus: .ok, headers: [:], body: byteBuffer)
                return .result(response)
            }
        )

        _ = try await responseTask
        XCTAssertNotNil(inMemoryLogging.entries.first { $0.message.description.hasPrefix("Request") })
        XCTAssertNotNil(inMemoryLogging.entries.first { $0.message.description.hasPrefix("Response") })
    }
}
