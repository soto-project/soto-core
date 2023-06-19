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
#if compiler(>=5.7) && os(Linux)
@preconcurrency import struct Foundation.Date
#else
import struct Foundation.Date
#endif
import Logging
import NIOCore
import NIOPosix
@testable import SotoCore
import SotoTestUtils
import XCTest

class RotatingCredentialProviderTests: XCTestCase {
    final class RotatingCredentialTestClient: CredentialProvider {
        typealias TestCallback = @Sendable () -> ExpiringCredential
        let callback: TestCallback

        init(_ callback: @escaping TestCallback) {
            self.callback = callback
        }

        func getCredential(logger: Logger) async throws -> Credential {
            self.callback()
        }
    }

    func testGetCredentialAndReuseIfStillValid() async throws {
        let group = MultiThreadedEventLoopGroup(numberOfThreads: 1)
        defer { XCTAssertNoThrow(try group.syncShutdownGracefully()) }
        let httpClient = HTTPClient(eventLoopGroupProvider: .shared(group))
        defer { XCTAssertNoThrow(try httpClient.syncShutdown()) }
        let loop = group.next()

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
        let context = CredentialProviderFactory.Context(httpClient: httpClient, eventLoop: loop, logger: Logger(label: "soto"), options: .init())
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

    func testGetCredentialHighlyConcurrent() async throws {
        let group = MultiThreadedEventLoopGroup(numberOfThreads: System.coreCount)
        defer { XCTAssertNoThrow(try group.syncShutdownGracefully()) }
        let httpClient = HTTPClient(eventLoopGroupProvider: .shared(group))
        defer { XCTAssertNoThrow(try httpClient.syncShutdown()) }
        let loop = group.next()

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
        let context = CredentialProviderFactory.Context(httpClient: httpClient, eventLoop: loop, logger: TestEnvironment.logger, options: .init())
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
        let loop = group.next()

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
        let context = CredentialProviderFactory.Context(httpClient: httpClient, eventLoop: loop, logger: TestEnvironment.logger, options: .init())
        let provider = RotatingCredentialProvider(context: context, provider: client)

        for _ in 0..<iterations {
            _ = try await provider.getCredential(logger: TestEnvironment.logger)
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
