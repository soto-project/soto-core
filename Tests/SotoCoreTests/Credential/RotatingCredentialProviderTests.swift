//===----------------------------------------------------------------------===//
//
// This source file is part of the Soto for AWS open source project
//
// Copyright (c) 2017-2022 the Soto project authors
// Licensed under Apache License v2.0
//
// See LICENSE.txt for license information
// See CONTRIBUTORS.txt for the list of Soto project authors
//
// SPDX-License-Identifier: Apache-2.0
//
//===----------------------------------------------------------------------===//

import AsyncHTTPClient
import Logging
import NIOConcurrencyHelpers
import NIOCore
import NIOPosix
@testable import SotoCore
import SotoTestUtils
import XCTest

class RotatingCredentialProviderTests: XCTestCase {
    final class MetaDataTestClient: CredentialProvider {
        #if compiler(>=5.6)
        typealias TestCallback = @Sendable (EventLoop) -> EventLoopFuture<ExpiringCredential>
        #else
        typealias TestCallback = (EventLoop) -> EventLoopFuture<ExpiringCredential>
        #endif
        let callback: TestCallback

        init(_ callback: @escaping TestCallback) {
            self.callback = callback
        }

        func getCredential(on eventLoop: EventLoop, logger: Logger) -> EventLoopFuture<Credential> {
            eventLoop.flatSubmit {
                return self.callback(eventLoop).map { $0 }
            }
        }
    }

    func testGetCredentialAndReuseIfStillValid() {
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

        let count = NIOAtomic<Int>.makeAtomic(value: 0)
        let client = MetaDataTestClient {
            count.add(1)
            return $0.makeSucceededFuture(cred)
        }
        let context = CredentialProviderFactory.Context(httpClient: httpClient, eventLoop: loop, logger: Logger(label: "soto"), options: .init())
        let provider = RotatingCredentialProvider(context: context, provider: client)

        // get credentials for first time
        var returned: Credential?
        XCTAssertNoThrow(returned = try provider.getCredential(on: loop, logger: Logger(label: "soto")).wait())

        XCTAssertEqual(returned?.accessKeyId, cred.accessKeyId)
        XCTAssertEqual(returned?.secretAccessKey, cred.secretAccessKey)
        XCTAssertEqual(returned?.sessionToken, cred.sessionToken)
        XCTAssertEqual((returned as? TestExpiringCredential)?.expiration, cred.expiration)

        // get credentials a second time, callback must not be hit
        XCTAssertNoThrow(returned = try provider.getCredential(on: loop, logger: Logger(label: "soto")).wait())
        XCTAssertEqual(returned?.accessKeyId, cred.accessKeyId)
        XCTAssertEqual(returned?.secretAccessKey, cred.secretAccessKey)
        XCTAssertEqual(returned?.sessionToken, cred.sessionToken)
        XCTAssertEqual((returned as? TestExpiringCredential)?.expiration, cred.expiration)

        // ensure callback was only hit once
        XCTAssertEqual(count.load(), 1)
    }

    func testGetCredentialHighlyConcurrent() {
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

        let promise = loop.makePromise(of: ExpiringCredential.self)

        let count = NIOAtomic<Int>.makeAtomic(value: 0)
        let count2 = NIOAtomic<Int>.makeAtomic(value: 0)
        let client = MetaDataTestClient { _ in
            count.add(1)
            return promise.futureResult
        }
        let context = CredentialProviderFactory.Context(httpClient: httpClient, eventLoop: loop, logger: TestEnvironment.logger, options: .init())
        let provider = RotatingCredentialProvider(context: context, provider: client)

        var resultFutures = [EventLoopFuture<Void>]()
        var setupFutures = [EventLoopFuture<Void>]()
        let iterations = 500
        for _ in 0..<iterations {
            let loop = group.next()
            let setupPromise = loop.makePromise(of: Void.self)
            setupFutures.append(setupPromise.futureResult)
            let future: EventLoopFuture<Void> = loop.flatSubmit {
                // this should be executed right away
                defer {
                    setupPromise.succeed(())
                }

                return provider.getCredential(on: loop, logger: TestEnvironment.logger).map { returned in
                    // this should be executed after the promise is fulfilled.
                    XCTAssertEqual(returned.accessKeyId, cred.accessKeyId)
                    XCTAssertEqual(returned.secretAccessKey, cred.secretAccessKey)
                    XCTAssertEqual(returned.sessionToken, cred.sessionToken)
                    XCTAssertEqual((returned as? TestExpiringCredential)?.expiration, cred.expiration)
                    XCTAssert(loop.inEventLoop)
                    count2.add(1)
                }
            }
            resultFutures.append(future)
        }

        // ensure all 10k have been setup
        XCTAssertNoThrow(try EventLoopFuture.whenAllSucceed(setupFutures, on: group.next()).wait())
        // succeed the promise call
        promise.succeed(cred)
        // ensure all 10k result futures have been forfilled
        XCTAssertNoThrow(try EventLoopFuture.whenAllSucceed(resultFutures, on: group.next()).wait())

        // ensure callback was only hit once
        XCTAssertEqual(count.load(), 1)
        XCTAssertEqual(count2.load(), iterations)
    }

    func testAlwaysGetNewTokenIfTokenLifetimeForUseIsShorterThanLifetime() {
        let group = MultiThreadedEventLoopGroup(numberOfThreads: 1)
        defer { XCTAssertNoThrow(try group.syncShutdownGracefully()) }
        let httpClient = HTTPClient(eventLoopGroupProvider: .shared(group))
        defer { XCTAssertNoThrow(try httpClient.syncShutdown()) }
        let loop = group.next()

        let iterations = 50
        let count = NIOAtomic.makeAtomic(value: 0)
        let client = MetaDataTestClient { eventLoop in
            count.add(1)
            let cred = TestExpiringCredential(
                accessKeyId: "abc123",
                secretAccessKey: "abc123",
                sessionToken: "abc123",
                expiration: Date(timeIntervalSinceNow: 60 * 2)
            )
            return eventLoop.makeSucceededFuture(cred)
        }
        let context = CredentialProviderFactory.Context(httpClient: httpClient, eventLoop: loop, logger: TestEnvironment.logger, options: .init())
        let provider = RotatingCredentialProvider(context: context, provider: client)

        for _ in 0..<iterations {
            XCTAssertNoThrow(_ = try provider.getCredential(on: loop, logger: TestEnvironment.logger).wait())
        }
        XCTAssertEqual(count.load(), iterations)
    }
}

/// Provide AWS credentials directly
struct TestExpiringCredential: ExpiringCredential {
    let accessKeyId: String
    let secretAccessKey: String
    let sessionToken: String?
    let expiration: Date?

    init(accessKeyId: String, secretAccessKey: String, sessionToken: String? = nil, expiration: Date? = nil) {
        self.accessKeyId = accessKeyId
        self.secretAccessKey = secretAccessKey
        self.sessionToken = sessionToken
        self.expiration = expiration
    }

    func isExpiring(within interval: TimeInterval) -> Bool {
        if let expiration = self.expiration {
            return expiration.timeIntervalSinceNow < interval
        }
        return false
    }
}
