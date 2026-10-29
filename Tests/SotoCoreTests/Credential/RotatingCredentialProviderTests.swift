//===----------------------------------------------------------------------===//
//
// This source file is part of the Soto for AWS open source project
//
// Copyright (c) 2017-2026 the Soto project authors
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
import Testing

@testable import SotoCore

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif

struct RotatingCredentialProviderTests {
    final class RotatingCredentialTestClient: CredentialProvider {
        typealias TestCallback = @Sendable () async throws -> Credential
        let callback: TestCallback

        init(_ callback: @escaping TestCallback) {
            self.callback = callback
        }

        func getCredential(logger: Logger) async throws -> Credential {
            try await self.callback()
        }
    }

    @Test func testSetupShutdown() async throws {
        let httpClient = HTTPClient.shared

        let client = RotatingCredentialTestClient {
            try await Task.sleep(nanoseconds: 5_000_000_000)
            Issue.record("Should not get here")
            return Credential(
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

    @Test func testGetCredentialAndReuseIfStillValid() async throws {
        let httpClient = HTTPClient.shared

        let cred = Credential(
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

        #expect(returned.accessKeyId == cred.accessKeyId)
        #expect(returned.secretAccessKey == cred.secretAccessKey)
        #expect(returned.sessionToken == cred.sessionToken)
        #expect(returned.expiration == cred.expiration)

        // get credentials a second time, callback must not be hit
        returned = try await provider.getCredential(logger: Logger(label: "soto"))

        #expect(returned.accessKeyId == cred.accessKeyId)
        #expect(returned.secretAccessKey == cred.secretAccessKey)
        #expect(returned.sessionToken == cred.sessionToken)
        #expect(returned.expiration == cred.expiration)

        // ensure callback was only hit once
        #expect(count.load(ordering: .sequentiallyConsistent) == 1)
    }

    @Test func testGetCredentialAndGetNewOnesAsAboutToExpire() async throws {
        let httpClient = HTTPClient.shared

        let creds = [
            Credential(
                accessKeyId: "abc123",
                secretAccessKey: "abc123",
                sessionToken: "abc123",
                expiration: Date(timeIntervalSinceNow: 10)
            ),
            Credential(
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

        #expect(returned.accessKeyId == creds[0].accessKeyId)
        #expect(returned.secretAccessKey == creds[0].secretAccessKey)
        #expect(returned.sessionToken == creds[0].sessionToken)
        #expect(returned.expiration == creds[0].expiration)

        // get credentials a second time, callback must not be hit
        returned = try await provider.getCredential(logger: Logger(label: "soto"))

        #expect(returned.accessKeyId == creds[1].accessKeyId)
        #expect(returned.secretAccessKey == creds[1].secretAccessKey)
        #expect(returned.sessionToken == creds[1].sessionToken)
        #expect(returned.expiration == creds[1].expiration)

        // ensure callback was hit twice as we
        #expect(count.load(ordering: .sequentiallyConsistent) == 2)
    }

    @Test func testGetCredentialHighlyConcurrent() async throws {
        let httpClient = HTTPClient.shared

        let cred = Credential(
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
                    #expect(credential.accessKeyId == cred.accessKeyId)
                    #expect(credential.secretAccessKey == cred.secretAccessKey)
                    #expect(credential.sessionToken == cred.sessionToken)
                    #expect(credential.expiration == cred.expiration)
                    count2.wrappingIncrement(ordering: .sequentiallyConsistent)
                }
                try await group.waitForAll()
            }
        }
        // ensure callback was only hit once
        #expect(count.load(ordering: .sequentiallyConsistent) == 1)
        #expect(count2.load(ordering: .sequentiallyConsistent) == iterations)
    }

    /// Test that even though we are at the point where the token has almost expired
    /// we only kick off one token renew
    @Test func testAlwaysGetNewTokenIfTokenLifetimeForUseIsShorterThanLifetime() async throws {
        let httpClient = HTTPClient.shared

        let iterations = 50
        let count = ManagedAtomic(0)
        let client = RotatingCredentialTestClient {
            let currentCount = count.loadThenWrappingIncrement(ordering: .sequentiallyConsistent)
            return Credential(
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
        #expect(count.load(ordering: .sequentiallyConsistent) == 2)
    }
}
