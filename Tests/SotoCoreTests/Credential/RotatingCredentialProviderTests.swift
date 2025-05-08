//===----------------------------------------------------------------------===//
//
// This source file is part of the Soto for AWS open source project
//
// Copyright (c) 2017-2023 the Soto project authors
// Licensed under Apache License v2.0
//
// See LICENSE.txt for license information
// See CONTRIBUTORS.txt for the list of Soto project authors
//
// SPDX-License-Identifier: Apache-2.0
//
//===----------------------------------------------------------------------===//

import AsyncHTTPClient
import Atomics
import Logging
import NIOCore
import NIOPosix
import SotoTestUtils
import XCTest

import struct Foundation.Date

@testable import SotoCore

class RotatingCredentialProviderTests: XCTestCase {
    final class RotatingCredentialTestClient: CredentialProvider {
        typealias TestCallback = @Sendable () async throws -> ExpiringCredential
        let callback: TestCallback

        init(_ callback: @escaping TestCallback) {
            self.callback = callback
        }

        func getCredential(logger: Logger) async throws -> Credential {
            try await self.callback()
        }
    }

    func testSetupShutdown() async throws {
        let group = MultiThreadedEventLoopGroup(numberOfThreads: 1)
        defer { XCTAssertNoThrow(try group.syncShutdownGracefully()) }
        let httpClient = HTTPClient(eventLoopGroupProvider: .shared(group))
        defer { XCTAssertNoThrow(try httpClient.syncShutdown()) }

        let client = RotatingCredentialTestClient {
            try await Task.sleep(nanoseconds: 5_000_000_000)
            XCTFail("Should not get here")
            return TestExpiringCredential(
                accessKeyId: "abc123",
                secretAccessKey: "abc123",
                sessionToken: "abc123",
                expiration: Date(timeIntervalSinceNow: 24 * 60 * 60)
            )
        }
        let context = CredentialProviderFactory.Context(
            httpClient: httpClient,
            logger: Logger(label: "soto"),
            options: .init()
        )
        let provider = RotatingCredentialProvider(context: context, provider: client)
        try await provider.shutdown()
    }

    func testGetCredentialAndReuseIfStillValid() async throws {
        let group = MultiThreadedEventLoopGroup(numberOfThreads: 1)
        defer { XCTAssertNoThrow(try group.syncShutdownGracefully()) }
        let httpClient = HTTPClient(eventLoopGroupProvider: .shared(group))
        defer { XCTAssertNoThrow(try httpClient.syncShutdown()) }

        let cred = TestExpiringCredential(
            accessKeyId: "abc123",
            secretAccessKey: "abc123",
            sessionToken: "abc123",
            expiration: Date(timeIntervalSinceNow: 24 * 60 * 60)
        )

        let count = ManagedAtomic(0)
        let client = RotatingCredentialTestClient {
            count.wrappingIncrement(ordering: .sequentiallyConsistent)
            return cred
        }
        let context = CredentialProviderFactory.Context(httpClient: httpClient, logger: Logger(label: "soto"), options: .init())
        let provider = RotatingCredentialProvider(context: context, provider: client)

        // get credentials for first time
        var returned = try await provider.getCredential(logger: Logger(label: "soto"))

        XCTAssertEqual(returned.accessKeyId, cred.accessKeyId)
        XCTAssertEqual(returned.secretAccessKey, cred.secretAccessKey)
        XCTAssertEqual(returned.sessionToken, cred.sessionToken)
        XCTAssertEqual((returned as? TestExpiringCredential)?.expiration, cred.expiration)

        // get credentials a second time, callback must not be hit
        returned = try await provider.getCredential(logger: Logger(label: "soto"))

        XCTAssertEqual(returned.accessKeyId, cred.accessKeyId)
        XCTAssertEqual(returned.secretAccessKey, cred.secretAccessKey)
        XCTAssertEqual(returned.sessionToken, cred.sessionToken)
        XCTAssertEqual((returned as? TestExpiringCredential)?.expiration, cred.expiration)

        // ensure callback was only hit once
        XCTAssertEqual(count.load(ordering: .sequentiallyConsistent), 1)
    }

    func testGetCredentialAndGetNewOnesAsAboutToExpire() async throws {
        let group = MultiThreadedEventLoopGroup(numberOfThreads: 1)
        defer { XCTAssertNoThrow(try group.syncShutdownGracefully()) }
        let httpClient = HTTPClient(eventLoopGroupProvider: .shared(group))
        defer { XCTAssertNoThrow(try httpClient.syncShutdown()) }

        let creds = [
            TestExpiringCredential(
                accessKeyId: "abc123",
                secretAccessKey: "abc123",
                sessionToken: "abc123",
                expiration: Date(timeIntervalSinceNow: 10)
            ),
            TestExpiringCredential(
                accessKeyId: "def456",
                secretAccessKey: "def456",
                sessionToken: "def456",
                expiration: Date(timeIntervalSinceNow: 10)
            ),
        ]

        let count = ManagedAtomic(0)
        let client = RotatingCredentialTestClient {
            let cred = creds[count.load(ordering: .sequentiallyConsistent)]
            count.wrappingIncrement(ordering: .sequentiallyConsistent)
            return cred
        }
        let context = CredentialProviderFactory.Context(httpClient: httpClient, logger: Logger(label: "soto"), options: .init())
        let provider = RotatingCredentialProvider(context: context, provider: client)

        // get credentials for first time
        var returned = try await provider.getCredential(logger: Logger(label: "soto"))

        XCTAssertEqual(returned.accessKeyId, creds[0].accessKeyId)
        XCTAssertEqual(returned.secretAccessKey, creds[0].secretAccessKey)
        XCTAssertEqual(returned.sessionToken, creds[0].sessionToken)
        XCTAssertEqual((returned as? TestExpiringCredential)?.expiration, creds[0].expiration)

        // get credentials a second time, callback must not be hit
        returned = try await provider.getCredential(logger: Logger(label: "soto"))

        XCTAssertEqual(returned.accessKeyId, creds[1].accessKeyId)
        XCTAssertEqual(returned.secretAccessKey, creds[1].secretAccessKey)
        XCTAssertEqual(returned.sessionToken, creds[1].sessionToken)
        XCTAssertEqual((returned as? TestExpiringCredential)?.expiration, creds[1].expiration)

        // ensure callback was hit twice as we
        XCTAssertEqual(count.load(ordering: .sequentiallyConsistent), 2)
    }

    func testGetCredentialHighlyConcurrent() async throws {
        let group = MultiThreadedEventLoopGroup(numberOfThreads: System.coreCount)
        defer { XCTAssertNoThrow(try group.syncShutdownGracefully()) }
        let httpClient = HTTPClient(eventLoopGroupProvider: .shared(group))
        defer { XCTAssertNoThrow(try httpClient.syncShutdown()) }

        let cred = TestExpiringCredential(
            accessKeyId: "abc123",
            secretAccessKey: "abc123",
            sessionToken: "abc123",
            expiration: Date(timeIntervalSinceNow: 60 * 5)
        )

        let count = ManagedAtomic(0)
        let count2 = ManagedAtomic(0)
        let client = RotatingCredentialTestClient {
            count.wrappingIncrement(ordering: .sequentiallyConsistent)
            return cred
        }
        let context = CredentialProviderFactory.Context(httpClient: httpClient, logger: TestEnvironment.logger, options: .init())
        let provider = RotatingCredentialProvider(context: context, provider: client)

        let iterations = 500
        try await withThrowingTaskGroup(of: Void.self) { group in
            for _ in 0..<iterations {
                group.addTask {
                    let credential = try await provider.getCredential(logger: TestEnvironment.logger)
                    // this should be executed after the promise is fulfilled.
                    XCTAssertEqual(credential.accessKeyId, cred.accessKeyId)
                    XCTAssertEqual(credential.secretAccessKey, cred.secretAccessKey)
                    XCTAssertEqual(credential.sessionToken, cred.sessionToken)
                    XCTAssertEqual((credential as? TestExpiringCredential)?.expiration, cred.expiration)
                    count2.wrappingIncrement(ordering: .sequentiallyConsistent)
                }
                try await group.waitForAll()
            }
        }
        // ensure callback was only hit once
        XCTAssertEqual(count.load(ordering: .sequentiallyConsistent), 1)
        XCTAssertEqual(count2.load(ordering: .sequentiallyConsistent), iterations)
    }

    /// Test that even though we are at the point where the token has almost expired
    /// we only kick off one token renew
    func testAlwaysGetNewTokenIfTokenLifetimeForUseIsShorterThanLifetime() async throws {
        let group = MultiThreadedEventLoopGroup(numberOfThreads: 1)
        defer { XCTAssertNoThrow(try group.syncShutdownGracefully()) }
        let httpClient = HTTPClient(eventLoopGroupProvider: .shared(group))
        defer { XCTAssertNoThrow(try httpClient.syncShutdown()) }

        let iterations = 50
        let count = ManagedAtomic(0)
        let client = RotatingCredentialTestClient {
            let currentCount = count.loadThenWrappingIncrement(ordering: .sequentiallyConsistent)
            return TestExpiringCredential(
                accessKeyId: "abc123",
                secretAccessKey: "abc123",
                sessionToken: "abc123",
                expiration: currentCount == 0 ? Date(timeIntervalSinceNow: 60 * 2) : Date.distantFuture
            )
        }
        let context = CredentialProviderFactory.Context(httpClient: httpClient, logger: TestEnvironment.logger, options: .init())
        let provider = RotatingCredentialProvider(context: context, provider: client)

        for _ in 0..<iterations {
            _ = try await provider.getCredential(logger: TestEnvironment.logger)
            await Task.yield()
            await Task.yield()
        }
        XCTAssertEqual(count.load(ordering: .sequentiallyConsistent), 2)
    }
}

/// Provide AWS credentials directly
struct TestExpiringCredential: ExpiringCredential {
    let accessKeyId: String
    let secretAccessKey: String
    let sessionToken: String?
    let expiration: Date

    init(accessKeyId: String, secretAccessKey: String, sessionToken: String? = nil, expiration: Date = Date.distantFuture) {
        self.accessKeyId = accessKeyId
        self.secretAccessKey = secretAccessKey
        self.sessionToken = sessionToken
        self.expiration = expiration
    }
}
