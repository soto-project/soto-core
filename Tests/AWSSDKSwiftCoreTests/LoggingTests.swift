//===----------------------------------------------------------------------===//
//
// This source file is part of the AWSSDKSwift open source project
//
// Copyright (c) 2017-2020 the AWSSDKSwift project authors
// Licensed under Apache License v2.0
//
// See LICENSE.txt for license information
// See CONTRIBUTORS.txt for the list of AWSSDKSwift project authors
//
// SPDX-License-Identifier: Apache-2.0
//
//===----------------------------------------------------------------------===//

@testable import AWSSDKSwiftCore
import AWSTestUtils
import Logging
import NIOConcurrencyHelpers
import XCTest

class LoggingTests: XCTestCase {
    func testRequestIdIncrements() {
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

        let response = client.execute(operation: "test1", path: "/", httpMethod: .GET, config: config, context: .init(logger: logger))
        let response2 = client.execute(operation: "test2", path: "/", httpMethod: .GET, config: config, context: .init(logger: logger))

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

        XCTAssertNoThrow(_ = try response.wait())
        XCTAssertNoThrow(_ = try response2.wait())
        let requestId1 = logCollection.filter(metadata: "aws-operation", with: "test1").first?.metadata["aws-request-id"]
        let requestId2 = logCollection.filter(metadata: "aws-operation", with: "test2").first?.metadata["aws-request-id"]
        XCTAssertNotNil(requestId1)
        XCTAssertNotNil(requestId2)
        XCTAssertNotEqual(requestId1, requestId2)
    }

    func testAWSRequestResponse() throws {
        let logCollection = LoggingCollector.Logs()
        var logger = Logger(label: "LoggingTests", factory: { _ in LoggingCollector(logCollection) })
        logger.logLevel = .trace
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

        let response = client.execute(operation: "TestOperation", path: "/", httpMethod: .GET, config: config, context: .init(logger: logger))

        XCTAssertNoThrow(try server.processRaw { _ in
            return .result(.ok, continueProcessing: false)
        })

        XCTAssertNoThrow(_ = try response.wait())
        let requestEntry = try XCTUnwrap(logCollection.filter(message: "AWS Request").first)
        XCTAssertEqual(requestEntry.level, .info)
        XCTAssertEqual(requestEntry.metadata["aws-operation"], "TestOperation")
        XCTAssertEqual(requestEntry.metadata["aws-service"], "test-service")
        let responseEntry = try XCTUnwrap(logCollection.filter(message: "AWS Response").first)
        XCTAssertEqual(responseEntry.level, .trace)
        XCTAssertEqual(responseEntry.metadata["aws-operation"], "TestOperation")
        XCTAssertEqual(responseEntry.metadata["aws-service"], "test-service")
    }

    func testAWSError() {
        let logCollection = LoggingCollector.Logs()
        let logger = Logger(label: "LoggingTests", factory: { _ in LoggingCollector(logCollection) })
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

        let response = client.execute(operation: "test", path: "/", httpMethod: .GET, config: config, context: .init(logger: logger))

        XCTAssertNoThrow(try server.processRaw { _ in
            return .error(.accessDenied, continueProcessing: false)
        })

        XCTAssertThrowsError(_ = try response.wait())
        XCTAssertEqual(logCollection.filter(metadata: "aws-error-code", with: "AccessDenied").first?.message, "AWS Error")
        XCTAssertEqual(logCollection.filter(metadata: "aws-error-code", with: "AccessDenied").first?.level, .error)
    }

    func testRetryRequest() {
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

        let response = client.execute(operation: "test1", path: "/", httpMethod: .GET, config: config, context: .init(logger: logger))

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

        XCTAssertNoThrow(_ = try response.wait())
        XCTAssertEqual(logCollection.filter(metadata: "aws-retry-time").first?.message, "Retrying request")
        XCTAssertEqual(logCollection.filter(metadata: "aws-retry-time").first?.level, .info)
    }

    func testNoCredentialProvider() {
        let logCollection = LoggingCollector.Logs()
        let logger = Logger(label: "LoggingTests", factory: { _ in LoggingCollector(logCollection, logLevel: .trace) })
        let client = createAWSClient(credentialProvider: .selector(.custom { _ in return NullCredentialProvider() }))
        defer { XCTAssertNoThrow(try client.syncShutdown()) }
        let serviceConfig = createServiceConfig()
        XCTAssertThrowsError(try client.execute(
            operation: "Test",
            path: "/",
            httpMethod: .GET,
            config: serviceConfig,
            context: .init(logger: logger)
        ).wait())
        XCTAssertNotNil(logCollection.filter(metadata: "aws-error-message", with: "No credential provider found").first)
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

        private var lock = Lock()
        private var logs: [Entry] = []

        var allEntries: [Entry] { return self.lock.withLock { logs } }

        func append(level: Logger.Level, message: Logger.Message, metadata: Logger.Metadata?) {
            self.lock.withLock {
                self.logs.append(Entry(
                    level: level,
                    message: message.description,
                    metadata: metadata?.mapValues { $0.description } ?? [:]
                ))
            }
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
