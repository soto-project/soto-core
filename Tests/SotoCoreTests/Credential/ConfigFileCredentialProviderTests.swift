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
    // MARK: - Credential Provider

    func makeContext() throws -> (CredentialProviderFactory.Context, MultiThreadedEventLoopGroup, HTTPClient) {
        let eventLoopGroup = MultiThreadedEventLoopGroup(numberOfThreads: 1)
        let eventLoop = eventLoopGroup.next()
        let httpClient = HTTPClient(eventLoopGroupProvider: .shared(eventLoop))
        return (.init(httpClient: httpClient, eventLoop: eventLoop, logger: TestEnvironment.logger), eventLoopGroup, httpClient)
    }

    func testCredentialProvider() throws {
        let credentials = ConfigFileLoader.ProfileCredentials(
            accessKey: "foo",
            secretAccessKey: "bar",
            sessionToken: nil,
            roleArn: nil,
            roleSessionName: nil,
            sourceProfile: nil,
            credentialSource: nil)
        let (context, eventLoopGroup, httpClient) = try makeContext()

        defer {
            try? httpClient.syncShutdown()
            try? eventLoopGroup.syncShutdownGracefully()
        }

        let provider = try ConfigFileCredentialProvider.credentialProvider(
            from: credentials,
            config: nil,
            context: context
        )
        XCTAssertEqual((provider as? StaticCredential)?.accessKeyId, "foo")
        XCTAssertEqual((provider as? StaticCredential)?.secretAccessKey, "bar")
    }

    func testCredentialProviderSTSAssumeRole() throws {
        let credentials = ConfigFileLoader.ProfileCredentials(
            accessKey: "foo",
            secretAccessKey: "bar",
            sessionToken: nil,
            roleArn: "arn",
            roleSessionName: nil,
            sourceProfile: "baz",
            credentialSource: nil)
        let (context, eventLoopGroup, httpClient) = try makeContext()

        defer {
            try? httpClient.syncShutdown()
            try? eventLoopGroup.syncShutdownGracefully()
        }

        let provider = try ConfigFileCredentialProvider.credentialProvider(
            from: credentials,
            config: nil,
            context: context
        )
        XCTAssertTrue(provider is RotatingCredentialProvider)
        XCTAssertTrue((provider as? RotatingCredentialProvider)?.provider is STSAssumeRoleCredentialProvider)
    }

    func testCredentialProviderCredentialSource() throws {
        let credentials = ConfigFileLoader.ProfileCredentials(
            accessKey: "foo",
            secretAccessKey: "bar",
            sessionToken: nil,
            roleArn: "arn",
            roleSessionName: nil,
            sourceProfile: nil,
            credentialSource: .ec2Instance)
        let (context, eventLoopGroup, httpClient) = try makeContext()

        defer {
            try? httpClient.syncShutdown()
            try? eventLoopGroup.syncShutdownGracefully()
        }

        do {
            _ = try ConfigFileCredentialProvider.credentialProvider(
                from: credentials,
                config: nil,
                context: context
            )
        } catch {
            XCTAssertEqual(error as? ConfigFileCredentialProviderError, ConfigFileCredentialProviderError.notSupported)
        }
    }

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
