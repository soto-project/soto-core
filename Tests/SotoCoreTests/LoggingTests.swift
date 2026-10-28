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

import HTTPTypes
import InMemoryLogging
import Logging
import NIOConcurrencyHelpers
import NIOCore
import NIOFoundationEssentialsCompat
import NIOHTTP1
import SotoTestUtils
import Synchronization
import XCTest

@testable import SotoCore

class LoggingTests: XCTestCase {
    func testRequestIdIncrements() async throws {
        let inMemoryLogging = InMemoryLogHandler()
        var logger = Logger(label: "LoggingTests", factory: { _ in inMemoryLogging })
        logger.logLevel = .trace

        let client = AWSClient(
            credentialProvider: .static(accessKeyId: "foo", secretAccessKey: "bar"),
            httpClient: MockAWSHTTPClient(),
            logger: logger
        )
        defer { XCTAssertNoThrow(try client.syncShutdown()) }

        let config = createServiceConfig(
            serviceProtocol: .json(version: "1.1")
        )

        _ = try await client.execute(operation: "test1", path: "/", httpMethod: .get, serviceConfig: config, logger: logger)
        _ = try await client.execute(operation: "test2", path: "/", httpMethod: .get, serviceConfig: config, logger: logger)

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
        let client = AWSClient(
            credentialProvider: .static(accessKeyId: "foo", secretAccessKey: "bar"),
            httpClient: MockAWSHTTPClient(),
            logger: logger
        )
        defer { XCTAssertNoThrow(try client.syncShutdown()) }
        let config = createServiceConfig(
            service: "test-service",
            serviceProtocol: .json(version: "1.1")
        )

        _ = try await client.execute(
            operation: "TestOperation",
            path: "/",
            httpMethod: .get,
            serviceConfig: config,
            logger: logger
        )
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
        let mockHTTPClient = MockAWSHTTPClient { request in
            MockAWSHTTPClient.HTTPError(status: .unauthorized, code: "AccessDenied").response(for: .json(version: "1.1"))
        }
        let client = AWSClient(
            credentialProvider: .static(accessKeyId: "foo", secretAccessKey: "bar"),
            options: .init(requestLogLevel: .debug, errorLogLevel: .info),
            httpClient: mockHTTPClient,
            logger: logger
        )
        defer { XCTAssertNoThrow(try client.syncShutdown()) }
        let config = createServiceConfig(
            serviceProtocol: .json(version: "1.1")
        )

        _ = try? await client.execute(operation: "test", path: "/", httpMethod: .get, serviceConfig: config, logger: logger)

        XCTAssertEqual(inMemoryLogging.entries.first { $0.metadata["aws-error-code"] == "AccessDenied" }?.message, "AWS Error")
        XCTAssertEqual(inMemoryLogging.entries.first { $0.metadata["aws-error-code"] == "AccessDenied" }?.level, .info)
    }

    func testRetryRequest() async throws {
        struct TestError: Error {}
        let inMemoryLogging = InMemoryLogHandler()
        var logger = Logger(label: "LoggingTests", factory: { _ in inMemoryLogging })
        logger.logLevel = .trace
        let count = Atomic(0)
        let mockHTTPClient = MockAWSHTTPClient { request in
            let (value, _) = count.add(1, ordering: .relaxed)
            if value == 0 {
                throw TestError()
            } else {
                return .init(response: .init(status: .ok))
            }
        }
        let client = AWSClient(
            credentialProvider: .static(accessKeyId: "foo", secretAccessKey: "bar"),
            httpClient: mockHTTPClient,
            logger: logger
        )
        defer { XCTAssertNoThrow(try client.syncShutdown()) }
        let config = createServiceConfig(
            serviceProtocol: .json(version: "1.1")
        )

        _ = try await client.execute(operation: "test1", path: "/", httpMethod: .get, serviceConfig: config, logger: logger)

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
                httpMethod: .get,
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
        let client = AWSClient(
            credentialProvider: .static(accessKeyId: "foo", secretAccessKey: "bar"),
            options: .init(requestLogLevel: .trace),
            httpClient: MockAWSHTTPClient(),
            logger: logger
        )
        defer { XCTAssertNoThrow(try client.syncShutdown()) }
        let config = createServiceConfig(
            service: "test-service",
            serviceProtocol: .json(version: "1.1")
        )

        _ = try await client.execute(
            operation: "TestOperation",
            path: "/",
            httpMethod: .get,
            serviceConfig: config,
            logger: logger
        )
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
        let mockHTTPClient = MockAWSHTTPClient { request in
            let output = Output(s: "TestOutputString")
            let byteBuffer = try JSONEncoder().encodeAsByteBuffer(output, allocator: ByteBufferAllocator())
            return .init(response: .init(status: .ok), body: .init(buffer: byteBuffer))
        }
        let client = AWSClient(
            credentialProvider: .static(accessKeyId: "foo", secretAccessKey: "bar"),
            middleware: AWSLoggingMiddleware(logger: logger, logLevel: .info),
            httpClient: mockHTTPClient,
            logger: logger
        )
        defer { XCTAssertNoThrow(try client.syncShutdown()) }

        let config = createServiceConfig(
            service: "test-service",
            serviceProtocol: .json(version: "1.1")
        )

        let _: Output = try await client.execute(
            operation: "TestOperation",
            path: "/",
            httpMethod: .get,
            serviceConfig: config,
            logger: traceLogger
        )
        XCTAssertNotNil(inMemoryLogging.entries.first { $0.message.description.hasPrefix("Request") })
        XCTAssertNotNil(inMemoryLogging.entries.first { $0.message.description.hasPrefix("Response") })
    }
}
