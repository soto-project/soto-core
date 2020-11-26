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
import NIO
@testable import SotoCore
import SotoTestUtils
import SotoXML
import XCTest

class ConfigFileCredentialProviderTests: XCTestCase {

    // MARK: Shared Credentials parsing (combined credentials & config)

//    func makeContext() throws -> CredentialProviderFactory.Context {
//        let eventLoopGroup = MultiThreadedEventLoopGroup(numberOfThreads: 1)
//        defer { XCTAssertNoThrow(try eventLoopGroup.syncShutdownGracefully()) }
//        let eventLoop = eventLoopGroup.next()
//        let httpClient = HTTPClient(eventLoopGroupProvider: .shared(eventLoop))
//        defer { XCTAssertNoThrow(try httpClient.syncShutdown()) }
//
//        return .init(httpClient: httpClient, eventLoop: eventLoop, logger: TestEnvironment.logger)
//    }
//
//    func testConfigFileCredentials() {
//        let profile = "profile1"
//        let accessKey = "FAKE-ACCESS-KEY123"
//        let secretKey = "Asecretreglkjrd"
//        let sessionToken = "xyz"
//        let credential = """
//        [\(profile)]
//        aws_access_key_id=\(accessKey)
//        aws_secret_access_key=\(secretKey)
//        aws_session_token=\(sessionToken)
//        """
//
//        var byteBuffer = ByteBufferAllocator().buffer(capacity: credential.utf8.count)
//        byteBuffer.writeString(credential)
//        var cred: CredentialProvider?
//        XCTAssertNoThrow(cred = try ConfigFileCredentialProvider.sharedCredentials(from: byteBuffer, for: profile, context: makeContext()))
//
//        XCTAssertEqual((cred as? StaticCredential)?.accessKeyId, accessKey)
//        XCTAssertEqual((cred as? StaticCredential)?.secretAccessKey, secretKey)
//        XCTAssertEqual((cred as? StaticCredential)?.sessionToken, sessionToken)
//    }
//
//    func testConfigFileCredentialsMissingAccessKey() {
//        let profile = "profile1"
//        let secretKey = "Asecretreglkjrd"
//        let credential = """
//        [\(profile)]
//        aws_secret_access_key=\(secretKey)
//        """
//
//        var byteBuffer = ByteBufferAllocator().buffer(capacity: credential.utf8.count)
//        byteBuffer.writeString(credential)
//        XCTAssertThrowsError(_ = try ConfigFileCredentialProvider.sharedCredentials(from: byteBuffer, for: profile, context: makeContext())) {
//            XCTAssertEqual($0 as? ConfigFileLoader.ConfigFileError, .missingAccessKeyId)
//        }
//    }
//
//    func testConfigFileCredentialsMissingSecretKey() {
//        let profile = "profile1"
//        let accessKey = "FAKE-ACCESS-KEY123"
//        let credential = """
//        [\(profile)]
//        aws_access_key_id=\(accessKey)
//        """
//
//        var byteBuffer = ByteBufferAllocator().buffer(capacity: credential.utf8.count)
//        byteBuffer.writeString(credential)
//        XCTAssertThrowsError(_ = try ConfigFileCredentialProvider.sharedCredentials(from: byteBuffer, for: profile, context: makeContext())) {
//            XCTAssertEqual($0 as? ConfigFileLoader.ConfigFileError, .missingSecretAccessKey)
//        }
//    }
//
//    func testConfigFileCredentialsMissingSessionToken() {
//        let profile = "profile1"
//        let accessKey = "FAKE-ACCESS-KEY123"
//        let secretKey = "Asecretreglkjrd"
//        let credential = """
//        [\(profile)]
//        aws_access_key_id=\(accessKey)
//        aws_secret_access_key=\(secretKey)
//        """
//
//        var byteBuffer = ByteBufferAllocator().buffer(capacity: credential.utf8.count)
//        byteBuffer.writeString(credential)
//        var cred: CredentialProvider?
//        XCTAssertNoThrow(cred = try ConfigFileCredentialProvider.sharedCredentials(from: byteBuffer, for: profile, context: makeContext()))
//
//        XCTAssertEqual((cred as? StaticCredential)?.accessKeyId, accessKey)
//        XCTAssertEqual((cred as? StaticCredential)?.secretAccessKey, secretKey)
//        XCTAssertNil((cred as? StaticCredential)?.sessionToken)
//    }
//
//    func testConfigFileCredentialsMissingProfile() {
//        let profile = "profile1"
//        let accessKey = "FAKE-ACCESS-KEY123"
//        let secretKey = "Asecretreglkjrd"
//        let credential = """
//        [\(profile)]
//        aws_access_key_id=\(accessKey)
//        aws_secret_access_key=\(secretKey)
//        """
//
//        var byteBuffer = ByteBufferAllocator().buffer(capacity: credential.utf8.count)
//        byteBuffer.writeString(credential)
//        XCTAssertThrowsError(_ = try ConfigFileCredentialProvider.sharedCredentials(from: byteBuffer, for: "profile2", context: makeContext())) {
//            XCTAssertEqual($0 as? ConfigFileLoader.ConfigFileError, .missingProfile("profile2"))
//        }
//    }
//
//    func testConfigFileCredentialsParseFailure() {
//        let credential = """
//        [default]
//        aws_access_key_id
//        """
//
//        var byteBuffer = ByteBufferAllocator().buffer(capacity: credential.utf8.count)
//        byteBuffer.writeString(credential)
//        XCTAssertThrowsError(_ = try ConfigFileCredentialProvider.sharedCredentials(from: byteBuffer, for: "default", context: makeContext())) {
//            XCTAssertEqual($0 as? ConfigFileLoader.ConfigFileError, .invalidCredentialFileSyntax)
//        }
//    }

    // MARK: - Load Shared Credentials from Disk

//    func testConfigFileCredentialINIParser() throws {
//        // setup
//        let credentials = """
//        [default]
//        aws_access_key_id = AWSACCESSKEYID
//        aws_secret_access_key = AWSSECRETACCESSKEY
//        """
//        let filename = "credentials"
//        let filenameURL = URL(fileURLWithPath: filename)
//        XCTAssertNoThrow(try Data(credentials.utf8).write(to: filenameURL))
//        defer { XCTAssertNoThrow(try FileManager.default.removeItem(at: filenameURL)) }
//
//        let eventLoopGroup = MultiThreadedEventLoopGroup(numberOfThreads: 1)
//        defer { XCTAssertNoThrow(try eventLoopGroup.syncShutdownGracefully()) }
//        let eventLoop = eventLoopGroup.next()
////        let path = filenameURL.absoluteString
//        let threadPool = NIOThreadPool(numberOfThreads: 1)
//        threadPool.start()
//        defer { XCTAssertNoThrow(try threadPool.syncShutdownGracefully()) }
//        let httpClient = HTTPClient(eventLoopGroupProvider: .shared(eventLoop))
//        defer { XCTAssertNoThrow(try httpClient.syncShutdown()) }
//        let fileIO = NonBlockingFileIO(threadPool: threadPool)
//
//        let future = ConfigFileCredentialProvider.getSharedCredentialsFromDisk(
//            credentialsFilePath: filenameURL.path,
//            configFilePath: nil,
//            profile: "default",
//            context: .init(httpClient: httpClient, eventLoop: eventLoop, logger: TestEnvironment.logger),
//            using: fileIO
//        )
//
//        var credential: CredentialProvider?
//        XCTAssertNoThrow(credential = try future.wait())
//        let staticCredential = try XCTUnwrap(credential as? StaticCredential)
//        XCTAssertEqual(staticCredential.accessKeyId, "AWSACCESSKEYID")
//        XCTAssertEqual(staticCredential.secretAccessKey, "AWSSECRETACCESSKEY")
//    }

    // MARK: - Config File Credentials Provider

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

        let provider = factory.createProvider(context: .init(httpClient: httpClient, eventLoop: eventLoop, logger: TestEnvironment.logger))

        var credential: Credential?
        XCTAssertNoThrow(credential = try provider.getCredential(on: eventLoop, logger: TestEnvironment.logger).wait())
        XCTAssertEqual(credential?.accessKeyId, "AWSACCESSKEYID")
        XCTAssertEqual(credential?.secretAccessKey, "AWSSECRETACCESSKEY")
    }

    func testAWSProfileConfigFile() {
        let credentials = """
        [test-profile]
        aws_access_key_id = TESTPROFILE-AWSACCESSKEYID
        aws_secret_access_key = TESTPROFILE-AWSSECRETACCESSKEY
        """
        Environment.set("test-profile", for: "AWS_PROFILE")
        defer { Environment.unset(name: "AWS_PROFILE") }

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

        let provider = factory.createProvider(context: .init(httpClient: httpClient, eventLoop: eventLoop, logger: TestEnvironment.logger))

        var credential: Credential?
        XCTAssertNoThrow(credential = try provider.getCredential(on: eventLoop, logger: TestEnvironment.logger).wait())
        XCTAssertEqual(credential?.accessKeyId, "TESTPROFILE-AWSACCESSKEYID")
        XCTAssertEqual(credential?.secretAccessKey, "TESTPROFILE-AWSSECRETACCESSKEY")
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

        let provider = factory.createProvider(context: .init(httpClient: httpClient, eventLoop: eventLoop, logger: TestEnvironment.logger))

        XCTAssertThrowsError(_ = try provider.getCredential(on: eventLoop, logger: TestEnvironment.logger).wait()) { error in
            print("\(error)")
            XCTAssertEqual(error as? CredentialProviderError, .noProvider)
        }
    }

    func testConfigFileShutdown() {
        let client = createAWSClient(credentialProvider: .configFile())
        XCTAssertNoThrow(try client.syncShutdown())
    }

}
