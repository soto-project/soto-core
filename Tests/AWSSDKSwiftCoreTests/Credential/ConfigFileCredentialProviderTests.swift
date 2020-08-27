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

import AsyncHTTPClient
@testable import AWSSDKSwiftCore
import AWSTestUtils
import NIO
import XCTest

class ConfigFileCredentialProviderTests: XCTestCase {
    func testConfigFileCredentials() {
        let profile = "profile1"
        let accessKey = "FAKE-ACCESS-KEY123"
        let secretKey = "Asecretreglkjrd"
        let sessionToken = "xyz"
        let credential = """
        [\(profile)]
        aws_access_key_id=\(accessKey)
        aws_secret_access_key=\(secretKey)
        aws_session_token=\(sessionToken)
        """

        var byteBuffer = ByteBufferAllocator().buffer(capacity: credential.utf8.count)
        byteBuffer.writeString(credential)
        var cred: StaticCredential?
        XCTAssertNoThrow(cred = try AWSConfigFileCredentialProvider.sharedCredentials(from: byteBuffer, for: profile))

        XCTAssertEqual(cred?.accessKeyId, accessKey)
        XCTAssertEqual(cred?.secretAccessKey, secretKey)
        XCTAssertEqual(cred?.sessionToken, sessionToken)
    }

    func testConfigFileCredentialsMissingAccessKey() {
        let profile = "profile1"
        let secretKey = "Asecretreglkjrd"
        let credential = """
        [\(profile)]
        aws_secret_access_key=\(secretKey)
        """

        var byteBuffer = ByteBufferAllocator().buffer(capacity: credential.utf8.count)
        byteBuffer.writeString(credential)
        XCTAssertThrowsError(_ = try AWSConfigFileCredentialProvider.sharedCredentials(from: byteBuffer, for: profile)) {
            XCTAssertEqual($0 as? AWSConfigFileCredentialProvider.ConfigFileError, .missingAccessKeyId)
        }
    }

    func testConfigFileCredentialsMissingSecretKey() {
        let profile = "profile1"
        let accessKey = "FAKE-ACCESS-KEY123"
        let credential = """
        [\(profile)]
        aws_access_key_id=\(accessKey)
        """

        var byteBuffer = ByteBufferAllocator().buffer(capacity: credential.utf8.count)
        byteBuffer.writeString(credential)
        XCTAssertThrowsError(_ = try AWSConfigFileCredentialProvider.sharedCredentials(from: byteBuffer, for: profile)) {
            XCTAssertEqual($0 as? AWSConfigFileCredentialProvider.ConfigFileError, .missingSecretAccessKey)
        }
    }

    func testConfigFileCredentialsMissingSessionToken() {
        let profile = "profile1"
        let accessKey = "FAKE-ACCESS-KEY123"
        let secretKey = "Asecretreglkjrd"
        let credential = """
        [\(profile)]
        aws_access_key_id=\(accessKey)
        aws_secret_access_key=\(secretKey)
        """

        var byteBuffer = ByteBufferAllocator().buffer(capacity: credential.utf8.count)
        byteBuffer.writeString(credential)
        var cred: StaticCredential?
        XCTAssertNoThrow(cred = try AWSConfigFileCredentialProvider.sharedCredentials(from: byteBuffer, for: profile))

        XCTAssertEqual(cred?.accessKeyId, accessKey)
        XCTAssertEqual(cred?.secretAccessKey, secretKey)
        XCTAssertNil(cred?.sessionToken)
    }

    func testConfigFileCredentialsMissingProfile() {
        let profile = "profile1"
        let accessKey = "FAKE-ACCESS-KEY123"
        let secretKey = "Asecretreglkjrd"
        let credential = """
        [\(profile)]
        aws_access_key_id=\(accessKey)
        aws_secret_access_key=\(secretKey)
        """

        var byteBuffer = ByteBufferAllocator().buffer(capacity: credential.utf8.count)
        byteBuffer.writeString(credential)
        XCTAssertThrowsError(_ = try AWSConfigFileCredentialProvider.sharedCredentials(from: byteBuffer, for: "profile2")) {
            XCTAssertEqual($0 as? AWSConfigFileCredentialProvider.ConfigFileError, .missingProfile("profile2"))
        }
    }

    func testConfigFileCredentialsParseFailure() {
        let credential = """
        [default]
        aws_access_key_id
        """

        var byteBuffer = ByteBufferAllocator().buffer(capacity: credential.utf8.count)
        byteBuffer.writeString(credential)
        XCTAssertThrowsError(_ = try AWSConfigFileCredentialProvider.sharedCredentials(from: byteBuffer, for: "default")) {
            XCTAssertEqual($0 as? AWSConfigFileCredentialProvider.ConfigFileError, .invalidCredentialFileSyntax)
        }
    }

    func testExpandTildeInFilePath() {
        let expandableFilePath = "~/.aws/credentials"
        let expandedNewPath = AWSConfigFileCredentialProvider.expandTildeInFilePath(expandableFilePath)

        #if os(Linux)
        XCTAssert(!expandedNewPath.hasPrefix("~"))
        #else
        // this doesn't work on linux because of SR-12843
        let expandedNSString = NSString(string: expandableFilePath).expandingTildeInPath
        XCTAssertEqual(expandedNewPath, expandedNSString)
        #endif

        let unexpandableFilePath = "/.aws/credentials"
        let unexpandedNewPath = AWSConfigFileCredentialProvider.expandTildeInFilePath(unexpandableFilePath)
        let unexpandedNSString = NSString(string: unexpandableFilePath).expandingTildeInPath

        XCTAssertEqual(unexpandedNewPath, unexpandedNSString)
        XCTAssertEqual(unexpandedNewPath, unexpandableFilePath)
    }

    func testConfigFileCredentialINIParser() {
        // setup
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
        defer { XCTAssertNoThrow(try eventLoopGroup.syncShutdownGracefully()) }
        let eventLoop = eventLoopGroup.next()
//        let path = filenameURL.absoluteString
        let future = AWSConfigFileCredentialProvider.fromSharedCredentials(credentialsFilePath: filenameURL.path, on: eventLoop)

        var credential: StaticCredential?
        XCTAssertNoThrow(credential = try future.wait())
        XCTAssertEqual(credential?.accessKeyId, "AWSACCESSKEYID")
        XCTAssertEqual(credential?.secretAccessKey, "AWSSECRETACCESSKEY")
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

        let provider = factory.createProvider(context: .init(httpClient: httpClient, eventLoop: eventLoop, logger: TestEnvironment.logger, baggage: .init()))

        var credential: Credential?
        XCTAssertNoThrow(credential = try provider.getCredential(on: eventLoop, context: TestEnvironment.context).wait())
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

        let provider = factory.createProvider(context: .init(httpClient: httpClient, eventLoop: eventLoop, logger: TestEnvironment.logger, baggage: .init()))

        XCTAssertThrowsError(_ = try provider.getCredential(on: eventLoop, context: TestEnvironment.context).wait()) { error in
            print("\(error)")
            XCTAssertEqual(error as? CredentialProviderError, .noProvider)
        }
    }

    func testConfigFileShutdown() {
        let client = createAWSClient(credentialProvider: .configFile())
        XCTAssertNoThrow(try client.syncShutdown())
    }
}
