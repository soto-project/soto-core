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
@testable import SotoCore
import SotoTestUtils
import XCTest

final class CredentialProviderTests: XCTestCase {
    func testCredentialProvider() async throws {
        let provider = StaticCredential(accessKeyId: "abc", secretAccessKey: "123", sessionToken: "xyz")

        let group = MultiThreadedEventLoopGroup(numberOfThreads: 1)
        defer { XCTAssertNoThrow(try group.syncShutdownGracefully()) }
        let credential = try await provider.getCredential(logger: TestEnvironment.logger)
        XCTAssertEqual(credential as? StaticCredential, provider)
    }

    // make sure getCredential in client CredentialProvider doesnt get called more than once
    func testDeferredCredentialProvider() async throws {
        final class MyCredentialProvider: CredentialProvider {
            let credentialProviderCalled = ManagedAtomic(0)

            init() {}

            func getCredential(logger: Logger) async throws -> Credential {
                self.credentialProviderCalled.wrappingIncrement(ordering: .sequentiallyConsistent)
                return StaticCredential(accessKeyId: "ACCESSKEYID", secretAccessKey: "SECRETACCESSKET")
            }
        }
        let eventLoopGroup = MultiThreadedEventLoopGroup(numberOfThreads: 1)
        defer { XCTAssertNoThrow(try eventLoopGroup.syncShutdownGracefully()) }
        let httpClient = HTTPClient(eventLoopGroupProvider: .shared(eventLoopGroup))
        defer { XCTAssertNoThrow(try httpClient.syncShutdown()) }
        let context = CredentialProviderFactory.Context(httpClient: httpClient, logger: TestEnvironment.logger, options: .init())
        let myCredentialProvider = MyCredentialProvider()
        let deferredProvider = DeferredCredentialProvider(context: context, provider: myCredentialProvider)
        _ = try await deferredProvider.getCredential(logger: TestEnvironment.logger)
        _ = try await deferredProvider.getCredential(logger: TestEnvironment.logger)
        XCTAssertEqual(myCredentialProvider.credentialProviderCalled.load(ordering: .sequentiallyConsistent), 1)
    }

    // Verify DeferredCredential provider handlers setup and immediate shutdown
    func testDeferredCredentialProviderSetupShutdown() async throws {
        final class MyCredentialProvider: CredentialProvider {
            init() {}
            func getCredential(logger: Logger) async throws -> Credential {
                try await Task.sleep(nanoseconds: 5_000_000_000)
                XCTFail("Should not get here")
                return StaticCredential(accessKeyId: "ACCESSKEYID", secretAccessKey: "SECRETACCESSKET")
            }
        }
        let eventLoopGroup = MultiThreadedEventLoopGroup(numberOfThreads: 1)
        defer { XCTAssertNoThrow(try eventLoopGroup.syncShutdownGracefully()) }
        let httpClient = HTTPClient(eventLoopGroupProvider: .shared(eventLoopGroup))
        defer { XCTAssertNoThrow(try httpClient.syncShutdown()) }

        let context = CredentialProviderFactory.Context(httpClient: httpClient, logger: TestEnvironment.logger, options: .init())
        let myCredentialProvider = MyCredentialProvider()
        let deferredProvider = DeferredCredentialProvider(context: context, provider: myCredentialProvider)
        try await deferredProvider.shutdown()
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

        let provider = factory.createProvider(context: .init(httpClient: httpClient, logger: TestEnvironment.logger, options: .init()))

        let credential = try await provider.getCredential(logger: TestEnvironment.logger)
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

        let provider = factory.createProvider(context: .init(httpClient: httpClient, logger: TestEnvironment.logger, options: .init()))

        do {
            _ = try await provider.getCredential(logger: TestEnvironment.logger)
            XCTFail("Should provide credential")
        } catch {
            XCTAssertEqual(error as? CredentialProviderError, .noProvider)
        }
    }

    func testCredentialSelectorShutdown() async throws {
        final class TestCredentialProvider: CredentialProvider {
            let hasShutdown = ManagedAtomic(false)
            init() {}

            func getCredential(logger: Logger) async throws -> Credential {
                return StaticCredential(accessKeyId: "", secretAccessKey: "")
            }

            func shutdown() async throws {
                self.hasShutdown.store(true, ordering: .sequentiallyConsistent)
            }
        }
        let eventLoopGroup = MultiThreadedEventLoopGroup(numberOfThreads: 1)
        defer { XCTAssertNoThrow(try eventLoopGroup.syncShutdownGracefully()) }
        let httpClient = HTTPClient(eventLoopGroupProvider: .shared(eventLoopGroup))
        defer { XCTAssertNoThrow(try httpClient.syncShutdown()) }
        let context = CredentialProviderFactory.Context(httpClient: httpClient, logger: TestEnvironment.logger, options: .init())
        let testCredentialProvider = TestCredentialProvider()

        let deferredProvider = DeferredCredentialProvider(context: context, provider: testCredentialProvider)
        try await deferredProvider.shutdown()
        XCTAssertEqual(testCredentialProvider.hasShutdown.load(ordering: .sequentiallyConsistent), true)
    }
}
