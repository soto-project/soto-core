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

import XCTest
import Logging
import NIOConcurrencyHelpers
import AWSTestUtils
import AWSSDKSwiftCore

class LoggingTests: XCTestCase {

    func testRequestIdIncrements() {
        let logCollection = LoggingCollector.Logs()
        let logger = Logger(label: "LoggingTests", factory: { _ in LoggingCollector(logCollection, logLevel: .trace)})
        let server = AWSTestServer(serviceProtocol: .json)
        defer { XCTAssertNoThrow(try server.stop()) }
        let client = AWSClient(
            credentialProvider: .default,
            httpClientProvider: .createNew,
            logger: logger)
        defer { XCTAssertNoThrow(try client.syncShutdown()) }
        let config = createServiceConfig(
            serviceProtocol: .json(version: "1.1"),
            endpoint: server.address
        )

        let response = client.execute(operation: "test1", path: "/", httpMethod: "GET", serviceConfig: config, logger: logger)
        let response2 = client.execute(operation: "test2", path: "/", httpMethod: "GET", serviceConfig: config, logger: logger)

        var count = 0
        XCTAssertNoThrow(try server.processRaw { request in
            let results: [AWSTestServer.Result<AWSTestServer.Response>] = [
                .result(.ok, continueProcessing: true),
                .result(.ok, continueProcessing: false)
            ]
            let result = results[count]
            count += 1
            return result
        })

        XCTAssertNoThrow(_ = try response.wait())
        XCTAssertNoThrow(_ = try response2.wait())
        let requestId1 = logCollection.filter(by: "aws-operation", with: "test1").first?.metadata["aws-request-id"]
        let requestId2 = logCollection.filter(by: "aws-operation", with: "test2").first?.metadata["aws-request-id"]
        XCTAssertNotNil(requestId1)
        XCTAssertNotNil(requestId2)
        XCTAssertNotEqual(requestId1, requestId2)
    }

    func testAWSError() {
        let logCollection = LoggingCollector.Logs()
        let logger = Logger(label: "LoggingTests", factory: { _ in LoggingCollector(logCollection)})
        let server = AWSTestServer(serviceProtocol: .json)
        defer { XCTAssertNoThrow(try server.stop()) }
        let client = AWSClient(
            credentialProvider: .default,
            httpClientProvider: .createNew,
            logger: logger)
        defer { XCTAssertNoThrow(try client.syncShutdown()) }
        let config = createServiceConfig(
            serviceProtocol: .json(version: "1.1"),
            endpoint: server.address
        )

        let response = client.execute(operation: "test", path: "/", httpMethod: "GET", serviceConfig: config, logger: logger)

        XCTAssertNoThrow(try server.processRaw { request in
            return .error(.accessDenied, continueProcessing: false)
        })

        XCTAssertThrowsError(_ = try response.wait())
        XCTAssertEqual(logCollection.filter(by: "aws-error-code", with: "AccessDenied").first?.message, "AWS error")
        XCTAssertEqual(logCollection.filter(by: "aws-error-code", with: "AccessDenied").first?.level, .error)
    }

    func testRetryRequest() {
        let logCollection = LoggingCollector.Logs()
        let logger = Logger(label: "LoggingTests", factory: { _ in LoggingCollector(logCollection, logLevel: .trace)})
        let server = AWSTestServer(serviceProtocol: .json)
        defer { XCTAssertNoThrow(try server.stop()) }
        let client = AWSClient(
            credentialProvider: .default,
            httpClientProvider: .createNew,
            logger: logger)
        defer { XCTAssertNoThrow(try client.syncShutdown()) }
        let config = createServiceConfig(
            serviceProtocol: .json(version: "1.1"),
            endpoint: server.address
        )

        let response = client.execute(operation: "test1", path: "/", httpMethod: "GET", serviceConfig: config, logger: logger)

        var count = 0
        XCTAssertNoThrow(try server.processRaw { request in
            let results: [AWSTestServer.Result<AWSTestServer.Response>] = [
                .error(.internal, continueProcessing: true),
                .result(.ok, continueProcessing: false)
            ]
            let result = results[count]
            count += 1
            return result
        })

        XCTAssertNoThrow(_ = try response.wait())
        XCTAssertEqual(logCollection.filter(by: "aws-retry-time").first?.message, "Retrying request")
        XCTAssertEqual(logCollection.filter(by: "aws-retry-time").first?.level, .info)
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
                self.logs.append(Entry(level: level,
                                       message: message.description,
                                       metadata: metadata?.mapValues { $0.description } ?? [:]))
            }
        }

        func filter(by metadata: String) -> [Entry] {
            return allEntries.filter { $0.metadata[metadata] != nil }
        }

        func filter(by metadata: String, with value: String) -> [Entry] {
            return allEntries.filter { $0.metadata[metadata] == value }
        }
    }

    init(_ logCollection: LoggingCollector.Logs, logLevel: Logger.Level = .info) {
        self.logLevel = logLevel
        self.logs = logCollection
        self.internalHandler = StreamLogHandler.standardOutput(label: "_internal_" )
        self.internalHandler.logLevel = logLevel
    }

    func log(level: Logger.Level, message: Logger.Message, metadata: Logger.Metadata?, file: String, function: String, line: UInt) {
        let metadata = self.metadata.merging(metadata ?? [:]) { $1 }
        internalHandler.log(level: logLevel, message: message, metadata: metadata, file:file, function: function, line: line)
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

