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
import Atomics
import Logging
import NIOCore
import NIOPosix
@testable import SotoCore
import SotoTestUtils
import XCTest

final class CredentialProviderTests: XCTestCase {
    func testCredentialProvider() async throws {
        let provider = StaticCredential(accessKeyId: "abc", secretAccessKey: "123", sessionToken: "xyz")

        let group = MultiThreadedEventLoopGroup(numberOfThreads: 1)
        defer { XCTAssertNoThrow(try group.syncShutdownGracefully()) }
        let loop = group.next()
        let credential = try await provider.getCredential(on: loop, logger: TestEnvironment.logger).get()
        XCTAssertEqual(credential as? StaticCredential, provider)
    }

    // make sure getCredential in client CredentialProvider doesnt get called more than once
    func testDeferredCredentialProvider() async throws {
        final class MyCredentialProvider: AsyncCredentialProvider {
            let credentialProviderCalled = ManagedAtomic(0)

            init() {}

            func getCredential(on eventLoop: EventLoop, logger: Logger) async throws -> Credential {
                self.credentialProviderCalled.wrappingIncrement(ordering: .sequentiallyConsistent)
                return StaticCredential(accessKeyId: "ACCESSKEYID", secretAccessKey: "SECRETACCESSKET")
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
        _ = try await deferredProvider.getCredential(on: eventLoop, logger: TestEnvironment.logger).get()
        _ = try await deferredProvider.getCredential(on: eventLoop, logger: TestEnvironment.logger).get()
        XCTAssertEqual(myCredentialProvider.credentialProviderCalled.load(ordering: .sequentiallyConsistent), 1)
    }

    func testConfigFileSuccess() async throws {
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

        let credential = try await provider.getCredential(on: eventLoop, logger: TestEnvironment.logger).get()
        XCTAssertEqual(credential.accessKeyId, "AWSACCESSKEYID")
        XCTAssertEqual(credential.secretAccessKey, "AWSSECRETACCESSKEY")
    }

    func testConfigFileNotAvailable() async throws {
        let filename = "credentials_not_existing"
        let filenameURL = URL(fileURLWithPath: filename)

        let eventLoopGroup = MultiThreadedEventLoopGroup(numberOfThreads: 1)
        let eventLoop = eventLoopGroup.next()
        defer { XCTAssertNoThrow(try eventLoopGroup.syncShutdownGracefully()) }
        let httpClient = HTTPClient(eventLoopGroupProvider: .shared(eventLoop))
        defer { XCTAssertNoThrow(try httpClient.syncShutdown()) }
        let factory = CredentialProviderFactory.configFile(credentialsFilePath: filenameURL.path)

        let provider = factory.createProvider(context: .init(httpClient: httpClient, eventLoop: eventLoop, logger: TestEnvironment.logger, options: .init()))

        do {
            _ = try await provider.getCredential(on: eventLoop, logger: TestEnvironment.logger).get()
            XCTFail("Should provide credential")
        } catch {
            XCTAssertEqual(error as? CredentialProviderError, .noProvider)
        }
    }

    func testCredentialSelectorShutdown() async throws {
        final class TestCredentialProvider: CredentialProvider {
            let hasShutdown = ManagedAtomic(false)
            init() {}

            func getCredential(on eventLoop: EventLoop, logger: Logger) -> EventLoopFuture<Credential> {
                return eventLoop.makeSucceededFuture(StaticCredential(accessKeyId: "", secretAccessKey: ""))
            }

            func shutdown(on eventLoop: EventLoop) -> EventLoopFuture<Void> {
                self.hasShutdown.store(true, ordering: .sequentiallyConsistent)
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
        try await deferredProvider.shutdown(on: eventLoopGroup.next()).get()
        XCTAssertEqual(testCredentialProvider.hasShutdown.load(ordering: .sequentiallyConsistent), true)
    }
}
