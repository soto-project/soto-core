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

import Logging
import NIOConcurrencyHelpers
@testable import SotoCore
import SotoTestUtils
import XCTest

class LoggingTests: XCTestCase {
    func testRequestIdIncrements() async throws {
        let logCollection = LoggingCollector.Logs()
        let logger = Logger(label: "LoggingTests", factory: { _ in LoggingCollector(logCollection, logLevel: .trace) })
        let server = AWSTestServer(serviceProtocol: .json)
        defer { XCTAssertNoThrow(try server.stop()) }
        let client = AWSClient(
            credentialProvider: .static(accessKeyId: "foo", secretAccessKey: "bar"),
            httpClientProvider: .createNew,
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
        XCTAssertNoThrow(try server.processRaw { _ in
            let results: [AWSTestServer.Result<AWSTestServer.Response>] = [
                .result(.ok, continueProcessing: true),
                .result(.ok, continueProcessing: false),
            ]
            let result = results[count]
            count += 1
            return result
        })

        try await responseTask
        try await response2Task
        let requestId1 = logCollection.filter(metadata: "aws-operation", with: "test1").first?.metadata["aws-request-id"]
        let requestId2 = logCollection.filter(metadata: "aws-operation", with: "test2").first?.metadata["aws-request-id"]
        XCTAssertNotNil(requestId1)
        XCTAssertNotNil(requestId2)
        XCTAssertNotEqual(requestId1, requestId2)
    }

    func testAWSRequestResponse() async throws {
        let logCollection = LoggingCollector.Logs()
        var logger = Logger(label: "LoggingTests", factory: { _ in LoggingCollector(logCollection) })
        logger.logLevel = .trace
        let traceLogger = logger
        let server = AWSTestServer(serviceProtocol: .json)
        defer { XCTAssertNoThrow(try server.stop()) }
        let client = AWSClient(
            credentialProvider: .static(accessKeyId: "foo", secretAccessKey: "bar"),
            httpClientProvider: .createNew,
            logger: logger
        )
        defer { XCTAssertNoThrow(try client.syncShutdown()) }
        let config = createServiceConfig(
            service: "test-service",
            serviceProtocol: .json(version: "1.1"),
            endpoint: server.address
        )

        async let responseTask: Void = client.execute(operation: "TestOperation", path: "/", httpMethod: .GET, serviceConfig: config, logger: traceLogger)

        XCTAssertNoThrow(try server.processRaw { _ in
            return .result(.ok, continueProcessing: false)
        })

        try await responseTask
        let requestEntry = try XCTUnwrap(logCollection.filter(message: "AWS Request").first)
        XCTAssertEqual(requestEntry.level, .debug)
        XCTAssertEqual(requestEntry.metadata["aws-operation"], "TestOperation")
        XCTAssertEqual(requestEntry.metadata["aws-service"], "test-service")
        let responseEntry = try XCTUnwrap(logCollection.filter(message: "AWS Response").first)
        XCTAssertEqual(responseEntry.level, .trace)
        XCTAssertEqual(responseEntry.metadata["aws-operation"], "TestOperation")
        XCTAssertEqual(responseEntry.metadata["aws-service"], "test-service")
    }

    func testAWSError() async throws {
        let logCollection = LoggingCollector.Logs()
        let logger = Logger(label: "LoggingTests", factory: { _ in LoggingCollector(logCollection) })
        let server = AWSTestServer(serviceProtocol: .json)
        defer { XCTAssertNoThrow(try server.stop()) }
        let client = AWSClient(
            credentialProvider: .static(accessKeyId: "foo", secretAccessKey: "bar"),
            options: .init(requestLogLevel: .debug, errorLogLevel: .info),
            httpClientProvider: .createNew,
            logger: logger
        )
        defer { XCTAssertNoThrow(try client.syncShutdown()) }
        let config = createServiceConfig(
            serviceProtocol: .json(version: "1.1"),
            endpoint: server.address
        )

        async let responseTask: Void = client.execute(operation: "test", path: "/", httpMethod: .GET, serviceConfig: config, logger: logger)

        XCTAssertNoThrow(try server.processRaw { _ in
            return .error(.accessDenied, continueProcessing: false)
        })

        try? await responseTask
        XCTAssertEqual(logCollection.filter(metadata: "aws-error-code", with: "AccessDenied").first?.message, "AWS Error")
        XCTAssertEqual(logCollection.filter(metadata: "aws-error-code", with: "AccessDenied").first?.level, .info)
    }

    func testRetryRequest() async throws {
        let logCollection = LoggingCollector.Logs()
        let logger = Logger(label: "LoggingTests", factory: { _ in LoggingCollector(logCollection, logLevel: .trace) })
        let server = AWSTestServer(serviceProtocol: .json)
        defer { XCTAssertNoThrow(try server.stop()) }
        let client = AWSClient(
            credentialProvider: .static(accessKeyId: "foo", secretAccessKey: "bar"),
            httpClientProvider: .createNew,
            logger: logger
        )
        defer { XCTAssertNoThrow(try client.syncShutdown()) }
        let config = createServiceConfig(
            serviceProtocol: .json(version: "1.1"),
            endpoint: server.address
        )

        async let responseTask: Void = client.execute(operation: "test1", path: "/", httpMethod: .GET, serviceConfig: config, logger: logger)

        var count = 0
        XCTAssertNoThrow(try server.processRaw { _ in
            let results: [AWSTestServer.Result<AWSTestServer.Response>] = [
                .error(.internal, continueProcessing: true),
                .result(.ok, continueProcessing: false),
            ]
            let result = results[count]
            count += 1
            return result
        })

        try await responseTask
        XCTAssertEqual(logCollection.filter(metadata: "aws-retry-time").first?.message, "Retrying request")
        XCTAssertEqual(logCollection.filter(metadata: "aws-retry-time").first?.level, .trace)
    }

    func testNoCredentialProvider() async throws {
        let logCollection = LoggingCollector.Logs()
        let logger = Logger(label: "LoggingTests", factory: { _ in LoggingCollector(logCollection, logLevel: .trace) })
        let client = createAWSClient(credentialProvider: .selector(.custom { _ in return NullCredentialProvider() }))
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
        XCTAssertNotNil(logCollection.filter(metadata: "aws-error-message", with: "No credential provider found.").first)
    }

    func testRequestLogLevel() async throws {
        let logCollection = LoggingCollector.Logs()
        var logger = Logger(label: "LoggingTests", factory: { _ in LoggingCollector(logCollection) })
        logger.logLevel = .trace
        let traceLogger = logger
        let server = AWSTestServer(serviceProtocol: .json)
        defer { XCTAssertNoThrow(try server.stop()) }
        let client = AWSClient(
            credentialProvider: .static(accessKeyId: "foo", secretAccessKey: "bar"),
            options: .init(requestLogLevel: .trace),
            httpClientProvider: .createNew,
            logger: logger
        )
        defer { XCTAssertNoThrow(try client.syncShutdown()) }
        let config = createServiceConfig(
            service: "test-service",
            serviceProtocol: .json(version: "1.1"),
            endpoint: server.address
        )

        async let responseTask: Void = client.execute(operation: "TestOperation", path: "/", httpMethod: .GET, serviceConfig: config, logger: traceLogger)

        XCTAssertNoThrow(try server.processRaw { _ in
            return .result(.ok, continueProcessing: false)
        })

        try await responseTask
        let requestEntry = try XCTUnwrap(logCollection.filter(message: "AWS Request").first)
        XCTAssertEqual(requestEntry.level, .trace)
    }

    func testLoggingMiddleware() async throws {
        struct Output: AWSDecodableShape & Encodable {
            let s: String
        }
        let logCollection = LoggingCollector.Logs()
        var logger = Logger(label: "LoggingTests", factory: { _ in LoggingCollector(logCollection) })
        logger.logLevel = .trace
        let traceLogger = logger
        let server = AWSTestServer(serviceProtocol: .json)
        defer { XCTAssertNoThrow(try server.stop()) }
        let client = AWSClient(
            credentialProvider: .static(accessKeyId: "foo", secretAccessKey: "bar"),
            middleware: AWSLoggingMiddleware(logger: logger, logLevel: .info),
            httpClientProvider: .createNew,
            logger: logger
        )
        defer { XCTAssertNoThrow(try client.syncShutdown()) }
        let config = createServiceConfig(
            service: "test-service",
            serviceProtocol: .json(version: "1.1"),
            endpoint: server.address
        )

        async let responseTask: Output = client.execute(operation: "TestOperation", path: "/", httpMethod: .GET, serviceConfig: config, logger: traceLogger)

        XCTAssertNoThrow(try server.processRaw { _ in
            let output = Output(s: "TestOutputString")
            let byteBuffer = try JSONEncoder().encodeAsByteBuffer(output, allocator: ByteBufferAllocator())
            let response = AWSTestServer.Response(httpStatus: .ok, headers: [:], body: byteBuffer)
            return .result(response)
        })

        _ = try await responseTask
        XCTAssertNotNil(logCollection.filter { $0.message.hasPrefix("Request") }.first)
        XCTAssertNotNil(logCollection.filter { $0.message.hasPrefix("Response") }.first)
    }
}

struct LoggingCollector: LogHandler {
    var metadata: Logger.Metadata = [:]
    var logLevel: Logger.Level
    var logs: Logs
    var internalHandler: LogHandler

    class Logs {
        struct Entry {
            var level: Logger.Level
            var message: String
            var metadata: [String: String]
        }

        private var lock = NIOLock()
        private var logs: [Entry] = []

        var allEntries: [Entry] { return self.lock.withLock { self.logs } }

        func append(level: Logger.Level, message: Logger.Message, metadata: Logger.Metadata?) {
            self.lock.withLock {
                self.logs.append(Entry(
                    level: level,
                    message: message.description,
                    metadata: metadata?.mapValues { $0.description } ?? [:]
                ))
            }
        }

        func filter(_ test: (Entry) -> Bool) -> [Entry] {
            return self.allEntries.filter { test($0) }
        }

        func filter(message: String) -> [Entry] {
            return self.allEntries.filter { $0.message == message }
        }

        func filter(metadata: String) -> [Entry] {
            return self.allEntries.filter { $0.metadata[metadata] != nil }
        }

        func filter(metadata: String, with value: String) -> [Entry] {
            return self.allEntries.filter { $0.metadata[metadata] == value }
        }
    }

    init(_ logCollection: LoggingCollector.Logs, logLevel: Logger.Level = .info) {
        self.logLevel = logLevel
        self.logs = logCollection
        self.internalHandler = StreamLogHandler.standardOutput(label: "_internal_")
        self.internalHandler.logLevel = logLevel
    }

    func log(level: Logger.Level, message: Logger.Message, metadata: Logger.Metadata?, source: String, file: String, function: String, line: UInt) {
        let metadata = self.metadata.merging(metadata ?? [:]) { $1 }
        self.internalHandler.log(level: level, message: message, metadata: metadata, source: source, file: file, function: function, line: line)
        self.logs.append(level: level, message: message, metadata: metadata)
    }

    subscript(metadataKey key: String) -> Logger.Metadata.Value? {
        get {
            return self.metadata[key]
        }
        set {
            self.metadata[key] = newValue
        }
    }
}
