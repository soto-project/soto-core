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

import AsyncHTTPClient
import Logging
import NIOConcurrencyHelpers
import NIOCore
import NIOPosix
@testable import SotoCore
import SotoTestUtils
#if compiler(>=5.6)
@preconcurrency import XCTest
#else
import XCTest
#endif

final class CredentialProviderTests: XCTestCase {
    func testCredentialProvider() {
        let cred = StaticCredential(accessKeyId: "abc", secretAccessKey: "123", sessionToken: "xyz")

        let group = MultiThreadedEventLoopGroup(numberOfThreads: 1)
        defer { XCTAssertNoThrow(try group.syncShutdownGracefully()) }
        let loop = group.next()
        var returned: Credential?
        XCTAssertNoThrow(returned = try cred.getCredential(on: loop, logger: TestEnvironment.logger).wait())

        XCTAssertEqual(returned as? StaticCredential, cred)
    }

    // make sure getCredential in client CredentialProvider doesnt get called more than once
    func testDeferredCredentialProvider() {
        final class MyCredentialProvider: CredentialProvider {
            let expectation = XCTestExpectation(description: "Credential provider called")

            init() {
                self.expectation.expectedFulfillmentCount = 1
                self.expectation.assertForOverFulfill = true
            }

            func getCredential(on eventLoop: EventLoop, logger: Logger) -> EventLoopFuture<Credential> {
                self.expectation.fulfill()
                return eventLoop.makeSucceededFuture(StaticCredential(accessKeyId: "ACCESSKEYID", secretAccessKey: "SECRETACCESSKET"))
            }
        }
        let eventLoopGroup = MultiThreadedEventLoopGroup(numberOfThreads: 1)
        defer { XCTAssertNoThrow(try eventLoopGroup.syncShutdownGracefully()) }
        let httpClient = HTTPClient(eventLoopGroupProvider: .shared(eventLoopGroup))
        defer { XCTAssertNoThrow(try httpClient.syncShutdown()) }
        let eventLoop = eventLoopGroup.next()
        let context = CredentialProviderFactory.Context(httpClient: httpClient, eventLoop: eventLoop, logger: TestEnvironment.logger, options: .init())
        let myCredentialProvider = MyCredentialProvider()
        let deferredProvider = DeferredCredentialProvider(context: context, provider: myCredentialProvider)
        XCTAssertNoThrow(_ = try deferredProvider.getCredential(on: eventLoop, logger: TestEnvironment.logger).wait())
        XCTAssertNoThrow(_ = try deferredProvider.getCredential(on: eventLoop, logger: TestEnvironment.logger).wait())
        wait(for: [myCredentialProvider.expectation], timeout: 5.0)
    }

    func testConfigFileSuccess() {
        let credentials = """
        [default]
        aws_access_key_id = AWSACCESSKEYID
        aws_secret_access_key = AWSSECRETACCESSKEY
        """
        let filename = "credentials"
        let filenameURL = URL(fileURLWithPath: filename)
        XCTAssertNoThrow(try Data(credentials.utf8).write(to: filenameURL))
        defer { XCTAssertNoThrow(try FileManager.default.removeItem(at: filenameURL)) }

        let eventLoopGroup = MultiThreadedEventLoopGroup(numberOfThreads: 1)
        let eventLoop = eventLoopGroup.next()
        defer { XCTAssertNoThrow(try eventLoopGroup.syncShutdownGracefully()) }
        let httpClient = HTTPClient(eventLoopGroupProvider: .shared(eventLoop))
        defer { XCTAssertNoThrow(try httpClient.syncShutdown()) }
        let factory = CredentialProviderFactory.configFile(credentialsFilePath: filenameURL.path)

        let provider = factory.createProvider(context: .init(httpClient: httpClient, eventLoop: eventLoop, logger: TestEnvironment.logger, options: .init()))

        var credential: Credential?
        XCTAssertNoThrow(credential = try provider.getCredential(on: eventLoop, logger: TestEnvironment.logger).wait())
        XCTAssertEqual(credential?.accessKeyId, "AWSACCESSKEYID")
        XCTAssertEqual(credential?.secretAccessKey, "AWSSECRETACCESSKEY")
    }

    func testConfigFileNotAvailable() {
        let filename = "credentials_not_existing"
        let filenameURL = URL(fileURLWithPath: filename)

        let eventLoopGroup = MultiThreadedEventLoopGroup(numberOfThreads: 1)
        let eventLoop = eventLoopGroup.next()
        defer { XCTAssertNoThrow(try eventLoopGroup.syncShutdownGracefully()) }
        let httpClient = HTTPClient(eventLoopGroupProvider: .shared(eventLoop))
        defer { XCTAssertNoThrow(try httpClient.syncShutdown()) }
        let factory = CredentialProviderFactory.configFile(credentialsFilePath: filenameURL.path)

        let provider = factory.createProvider(context: .init(httpClient: httpClient, eventLoop: eventLoop, logger: TestEnvironment.logger, options: .init()))

        XCTAssertThrowsError(_ = try provider.getCredential(on: eventLoop, logger: TestEnvironment.logger).wait()) { error in
            print("\(error)")
            XCTAssertEqual(error as? CredentialProviderError, .noProvider)
        }
    }

    func testCredentialSelectorShutdown() {
        final class TestCredentialProvider: CredentialProvider {
            let expectation = XCTestExpectation(description: "Has Shutdown")
            init() {
                self.expectation.expectedFulfillmentCount = 1
            }

            func getCredential(on eventLoop: EventLoop, logger: Logger) -> EventLoopFuture<Credential> {
                return eventLoop.makeSucceededFuture(StaticCredential(accessKeyId: "", secretAccessKey: ""))
            }

            func shutdown(on eventLoop: EventLoop) -> EventLoopFuture<Void> {
                self.expectation.fulfill()
                return eventLoop.makeSucceededFuture(())
            }
        }
        let eventLoopGroup = MultiThreadedEventLoopGroup(numberOfThreads: 1)
        defer { XCTAssertNoThrow(try eventLoopGroup.syncShutdownGracefully()) }
        let httpClient = HTTPClient(eventLoopGroupProvider: .shared(eventLoopGroup))
        defer { XCTAssertNoThrow(try httpClient.syncShutdown()) }
        let eventLoop = eventLoopGroup.next()
        let context = CredentialProviderFactory.Context(httpClient: httpClient, eventLoop: eventLoop, logger: TestEnvironment.logger, options: .init())
        let testCredentialProvider = TestCredentialProvider()
        let deferredProvider = DeferredCredentialProvider(context: context, provider: testCredentialProvider)
        XCTAssertNoThrow(try deferredProvider.shutdown(on: eventLoopGroup.next()).wait())

        wait(for: [testCredentialProvider.expectation], timeout: 5.0)
    }
}
