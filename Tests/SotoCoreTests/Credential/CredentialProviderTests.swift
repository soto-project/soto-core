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
import NIO
import NIOConcurrencyHelpers
@testable import SotoCore
import SotoTestUtils
import XCTest

class CredentialProviderTests: XCTestCase {
    func testCredentialProvider() {
        let cred = StaticCredential(accessKeyId: "abc", secretAccessKey: "123", sessionToken: "xyz")

        let group = MultiThreadedEventLoopGroup(numberOfThreads: 1)
        defer { XCTAssertNoThrow(try group.syncShutdownGracefully()) }
        let loop = group.next()
        var returned: Credential?
        XCTAssertNoThrow(returned = try cred.getCredential(on: loop, context: TestEnvironment.loggingContext).wait())

        XCTAssertEqual(returned as? StaticCredential, cred)
    }

    // make sure getCredential in client CredentialProvider doesnt get called more than once
    func testDeferredCredentialProvider() {
        class MyCredentialProvider: CredentialProvider {
            var alreadyCalled = false
            func getCredential(on eventLoop: EventLoop, context: LoggingContext) -> EventLoopFuture<Credential> {
                if self.alreadyCalled == false {
                    self.alreadyCalled = true
                    return eventLoop.makeSucceededFuture(StaticCredential(accessKeyId: "ACCESSKEYID", secretAccessKey: "SECRETACCESSKET"))
                } else {
                    return eventLoop.makeFailedFuture(CredentialProviderError.noProvider)
                }
            }
        }
        let eventLoopGroup = MultiThreadedEventLoopGroup(numberOfThreads: 1)
        defer { XCTAssertNoThrow(try eventLoopGroup.syncShutdownGracefully()) }
        let httpClient = HTTPClient(eventLoopGroupProvider: .shared(eventLoopGroup))
        defer { XCTAssertNoThrow(try httpClient.syncShutdown()) }
        let eventLoop = eventLoopGroup.next()
        let context = CredentialProviderFactory.Context(httpClient: httpClient, eventLoop: eventLoop, context: TestEnvironment.loggingContext, options: .init())
        let deferredProvider = DeferredCredentialProvider(context: context, provider: MyCredentialProvider())
        XCTAssertNoThrow(_ = try deferredProvider.getCredential(on: eventLoop, context: TestEnvironment.loggingContext).wait())
        XCTAssertNoThrow(_ = try deferredProvider.getCredential(on: eventLoop, context: TestEnvironment.loggingContext).wait())
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

        let provider = factory.createProvider(context: .init(httpClient: httpClient, eventLoop: eventLoop, context: TestEnvironment.loggingContext, options: .init()))

        var credential: Credential?
        XCTAssertNoThrow(credential = try provider.getCredential(on: eventLoop, context: TestEnvironment.loggingContext).wait())
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

        let provider = factory.createProvider(context: .init(httpClient: httpClient, eventLoop: eventLoop, context: TestEnvironment.loggingContext, options: .init()))

        XCTAssertThrowsError(_ = try provider.getCredential(on: eventLoop, context: TestEnvironment.loggingContext).wait()) { error in
            print("\(error)")
            XCTAssertEqual(error as? CredentialProviderError, .noProvider)
        }
    }

    func testCredentialSelectorShutdown() {
        class TestCredentialProvider: CredentialProvider {
            var active = true

            func getCredential(on eventLoop: EventLoop, context: LoggingContext) -> EventLoopFuture<Credential> {
                return eventLoop.makeSucceededFuture(StaticCredential(accessKeyId: "", secretAccessKey: ""))
            }

            func shutdown(on eventLoop: EventLoop) -> EventLoopFuture<Void> {
                self.active = false
                return eventLoop.makeSucceededFuture(())
            }

            deinit {
                XCTAssertEqual(active, false)
            }
        }
        class CredentialProviderOwner: CredentialProviderSelector {
            /// promise to find a credential provider
            let startupPromise: EventLoopPromise<CredentialProvider>
            let lock = Lock()
            var _internalProvider: CredentialProvider?

            init(eventLoop: EventLoop) {
                self.startupPromise = eventLoop.makePromise(of: CredentialProvider.self)
                self.startupPromise.futureResult.whenSuccess { result in
                    self.internalProvider = result
                }
                self.startupPromise.succeed(TestCredentialProvider())
            }
        }
        let elg = MultiThreadedEventLoopGroup(numberOfThreads: 1)
        defer { XCTAssertNoThrow(try elg.syncShutdownGracefully()) }
        let provider = CredentialProviderOwner(eventLoop: elg.next())
        XCTAssertNoThrow(try provider.shutdown(on: elg.next()).wait())
    }
}
