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
import AsyncHTTPClient
import Logging
import NIO
import NIOConcurrencyHelpers
import XCTest

class RotatingCredentialProviderTests: XCTestCase {

    class MetaDataTestClient: CredentialProvider {
        let callback: (EventLoop) -> EventLoopFuture<ExpiringCredential>

        init(_ callback: @escaping (EventLoop) -> EventLoopFuture<ExpiringCredential>) {
            self.callback = callback
        }

        func getCredential(on eventLoop: EventLoop, logger: Logger) -> EventLoopFuture<Credential> {
            eventLoop.flatSubmit() {
                self.callback(eventLoop).map { $0 }
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
            expiration: Date(timeIntervalSinceNow: 60 * 5))

        var hitCount = 0
        let client = MetaDataTestClient {
            hitCount += 1
            return $0.makeSucceededFuture(cred)
        }
        let context = CredentialProviderFactory.Context(httpClient: httpClient, eventLoop: loop, logger: AWSClient.loggingDisabled)
        let provider = RotatingCredentialProvider(context: context, provider: client)

        // get credentials for first time
        var returned: Credential?
        XCTAssertNoThrow(returned = try provider.getCredential(on: loop, logger: AWSClient.loggingDisabled).wait())

        XCTAssertEqual(returned?.accessKeyId, cred.accessKeyId)
        XCTAssertEqual(returned?.secretAccessKey, cred.secretAccessKey)
        XCTAssertEqual(returned?.sessionToken, cred.sessionToken)
        XCTAssertEqual((returned as? TestExpiringCredential)?.expiration, cred.expiration)

        // get credentials a second time, callback must not be hit
        XCTAssertNoThrow(returned = try provider.getCredential(on: loop, logger: AWSClient.loggingDisabled).wait())
        XCTAssertEqual(returned?.accessKeyId, cred.accessKeyId)
        XCTAssertEqual(returned?.secretAccessKey, cred.secretAccessKey)
        XCTAssertEqual(returned?.sessionToken, cred.sessionToken)
        XCTAssertEqual((returned as? TestExpiringCredential)?.expiration, cred.expiration)

        // ensure callback was only hit once
        XCTAssertEqual(hitCount, 1)
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
            expiration: Date(timeIntervalSinceNow: 60 * 5))

        let promise = loop.makePromise(of: ExpiringCredential.self)

        var hitCount = 0
        let client = MetaDataTestClient { _ in
            hitCount += 1
            return promise.futureResult
        }
        let context = CredentialProviderFactory.Context(httpClient: httpClient, eventLoop: loop, logger: AWSClient.loggingDisabled)
        let provider = RotatingCredentialProvider(context: context, provider: client)

        var resultFutures = [EventLoopFuture<Void>]()
        var setupFutures = [EventLoopFuture<Void>]()
        let fulFillCount = NIOAtomic<Int>.makeAtomic(value: 0)
        let iterations = 10000
        for _ in 0..<iterations {
            let loop = group.next()
            let setupPromise = loop.makePromise(of: Void.self)
            setupFutures.append(setupPromise.futureResult)
            let future: EventLoopFuture<Void> = loop.flatSubmit {
                // this should be executed right away
                defer {
                    setupPromise.succeed(())
                }

                return provider.getCredential(on: loop, logger: AWSClient.loggingDisabled).map { returned in
                    // this should be executed after the promise is fulfilled.
                    XCTAssertEqual(returned.accessKeyId, cred.accessKeyId)
                    XCTAssertEqual(returned.secretAccessKey, cred.secretAccessKey)
                    XCTAssertEqual(returned.sessionToken, cred.sessionToken)
                    XCTAssertEqual((returned as? TestExpiringCredential)?.expiration, cred.expiration)
                    XCTAssert(loop.inEventLoop)
                    fulFillCount.add(1)
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
        XCTAssertEqual(hitCount, 1)
        // ensure all waiting futures where fulfilled
        XCTAssertEqual(fulFillCount.load(), iterations)
    }

    func testAlwaysGetNewTokenIfTokenLifetimeForUseIsShorterThanLifetime() {
        let group = MultiThreadedEventLoopGroup(numberOfThreads: 1)
        defer { XCTAssertNoThrow(try group.syncShutdownGracefully()) }
        let httpClient = HTTPClient(eventLoopGroupProvider: .shared(group))
        defer { XCTAssertNoThrow(try httpClient.syncShutdown()) }
        let loop = group.next()

        var hitCount = 0
        let client = MetaDataTestClient { (eventLoop) in
            hitCount += 1
            let cred = TestExpiringCredential(
                accessKeyId: "abc123",
                secretAccessKey: "abc123",
                sessionToken: "abc123",
                expiration: Date(timeIntervalSinceNow: 60 * 2))
            return eventLoop.makeSucceededFuture(cred)
        }
        let context = CredentialProviderFactory.Context(httpClient: httpClient, eventLoop: loop, logger: AWSClient.loggingDisabled)
        let provider = RotatingCredentialProvider(context: context, provider: client)
        XCTAssertNoThrow(_ = try provider.getCredential(on: loop).wait())
        hitCount = 0
        
        let iterations = 100
        for _ in 0..<100 {
            XCTAssertNoThrow(_ = try provider.getCredential(on: loop, logger: AWSClient.loggingDisabled).wait())
        }

        // ensure callback was only hit once
        XCTAssertEqual(hitCount, iterations)
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
