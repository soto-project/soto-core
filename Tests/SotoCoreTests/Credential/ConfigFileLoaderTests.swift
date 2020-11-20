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

class ConfigFileLoadersTests: XCTestCase {

    // MARK: Shared Credentials parsing (combined credentials & config)

    func makeContext() throws -> CredentialProviderFactory.Context {
        let eventLoopGroup = MultiThreadedEventLoopGroup(numberOfThreads: 1)
        defer { XCTAssertNoThrow(try eventLoopGroup.syncShutdownGracefully()) }
        let eventLoop = eventLoopGroup.next()
        let httpClient = HTTPClient(eventLoopGroupProvider: .shared(eventLoop))
        defer { XCTAssertNoThrow(try httpClient.syncShutdown()) }

        return .init(httpClient: httpClient, eventLoop: eventLoop, logger: TestEnvironment.logger)
    }

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
        var cred: CredentialProvider?
        XCTAssertNoThrow(cred = try ConfigFileLoader.sharedCredentials(from: byteBuffer, for: profile, context: makeContext()))

        XCTAssertEqual((cred as? StaticCredential)?.accessKeyId, accessKey)
        XCTAssertEqual((cred as? StaticCredential)?.secretAccessKey, secretKey)
        XCTAssertEqual((cred as? StaticCredential)?.sessionToken, sessionToken)
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
        XCTAssertThrowsError(_ = try ConfigFileLoader.sharedCredentials(from: byteBuffer, for: profile, context: makeContext())) {
            XCTAssertEqual($0 as? ConfigFileLoader.ConfigFileError, .missingAccessKeyId)
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
        XCTAssertThrowsError(_ = try ConfigFileLoader.sharedCredentials(from: byteBuffer, for: profile, context: makeContext())) {
            XCTAssertEqual($0 as? ConfigFileLoader.ConfigFileError, .missingSecretAccessKey)
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
        var cred: CredentialProvider?
        XCTAssertNoThrow(cred = try ConfigFileLoader.sharedCredentials(from: byteBuffer, for: profile, context: makeContext()))

        XCTAssertEqual((cred as? StaticCredential)?.accessKeyId, accessKey)
        XCTAssertEqual((cred as? StaticCredential)?.secretAccessKey, secretKey)
        XCTAssertNil((cred as? StaticCredential)?.sessionToken)
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
        XCTAssertThrowsError(_ = try ConfigFileLoader.sharedCredentials(from: byteBuffer, for: "profile2", context: makeContext())) {
            XCTAssertEqual($0 as? ConfigFileLoader.ConfigFileError, .missingProfile("profile2"))
        }
    }

    func testConfigFileCredentialsParseFailure() {
        let credential = """
        [default]
        aws_access_key_id
        """

        var byteBuffer = ByteBufferAllocator().buffer(capacity: credential.utf8.count)
        byteBuffer.writeString(credential)
        XCTAssertThrowsError(_ = try ConfigFileLoader.sharedCredentials(from: byteBuffer, for: "default", context: makeContext())) {
            XCTAssertEqual($0 as? ConfigFileLoader.ConfigFileError, .invalidCredentialFileSyntax)
        }
    }

    // MARK: - Config File parsing

    func testConfigFileDefault() throws {
        let content = """
        [default]
        role_arn = arn:aws:iam::123456789012:role/marketingadminrole
        source_profile = user1
        region=us-west-2
        """
        var byteBuffer = ByteBufferAllocator().buffer(capacity: content.utf8.count)
        byteBuffer.writeString(content)

        let config = try ConfigFileLoader.loadProfileConfig(from: byteBuffer, for: ConfigFileLoader.default)
        XCTAssertEqual(config.roleArn, "arn:aws:iam::123456789012:role/marketingadminrole")
        XCTAssertEqual(config.sourceProfile, "user1")
        XCTAssertEqual(config.region, .uswest2)
    }

    func testConfigFileNamedProfile() throws {
        let content = """
        [default]
        region=us-west-2
        output=json

        [profile marketingadmin]
        role_arn = arn:aws:iam::123456789012:role/marketingadminrole
        source_profile = user1
        role_session_name = foo@example.com
        region = us-west-1
        """
        var byteBuffer = ByteBufferAllocator().buffer(capacity: content.utf8.count)
        byteBuffer.writeString(content)

        let config = try ConfigFileLoader.loadProfileConfig(from: byteBuffer, for: "marketingadmin")
        XCTAssertEqual(config.roleArn, "arn:aws:iam::123456789012:role/marketingadminrole")
        XCTAssertEqual(config.sourceProfile, "user1")
        XCTAssertEqual(config.roleSessionName, "foo@example.com")
        XCTAssertEqual(config.region, .uswest1)
    }

    func testConfigFileCredentialSourceEc2() throws {
        let content = """
        [profile marketingadmin]
        role_arn = arn:aws:iam::123456789012:role/marketingadminrole
        credential_source = Ec2InstanceMetadata
        """
        var byteBuffer = ByteBufferAllocator().buffer(capacity: content.utf8.count)
        byteBuffer.writeString(content)

        let config = try ConfigFileLoader.loadProfileConfig(from: byteBuffer, for: "marketingadmin")
        XCTAssertEqual(config.credentialSource, .ec2Instance)
    }

    func testConfigFileCredentialSourceEcs() throws {
        let content = """
        [profile marketingadmin]
        role_arn = arn:aws:iam::123456789012:role/marketingadminrole
        credential_source = EcsContainer
        """
        var byteBuffer = ByteBufferAllocator().buffer(capacity: content.utf8.count)
        byteBuffer.writeString(content)


        let config = try ConfigFileLoader.loadProfileConfig(from: byteBuffer, for: "marketingadmin")
        XCTAssertEqual(config.credentialSource, .ecsContainer)
    }

    func testConfigFileCredentialSourceEnvironment() throws {
        let content = """
        [profile marketingadmin]
        role_arn = arn:aws:iam::123456789012:role/marketingadminrole
        credential_source = Environment
        """
        var byteBuffer = ByteBufferAllocator().buffer(capacity: content.utf8.count)
        byteBuffer.writeString(content)


        let config = try ConfigFileLoader.loadProfileConfig(from: byteBuffer, for: "marketingadmin")
        XCTAssertEqual(config.credentialSource, .environment)
    }

    // MARK: - Credentials File parsing

    func testCredentialsDefault() throws {
        let content = """
        [default]
        aws_access_key_id=AKIAIOSFODNN7EXAMPLE
        aws_secret_access_key=wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY
        """
        var byteBuffer = ByteBufferAllocator().buffer(capacity: content.utf8.count)
        byteBuffer.writeString(content)

        let config = try ConfigFileLoader.loadCredentials(from: byteBuffer, for: ConfigFileLoader.default, sourceProfile: nil)
        XCTAssertEqual(config.accessKey, "AKIAIOSFODNN7EXAMPLE")
        XCTAssertEqual(config.secretAccessKey, "wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY")
    }

    func testCredentialsNamedProfile() throws {
        let content = """
        [default]
        aws_access_key_id=AKIAIOSFODNN7EXAMPLE
        aws_secret_access_key=wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY

        [user1]
        aws_access_key_id=AKIAI44QH8DHBEXAMPLE
        aws_secret_access_key=je7MtGbClwBF/2Zp9Utk/h3yCo8nvbEXAMPLEKEY
        """
        var byteBuffer = ByteBufferAllocator().buffer(capacity: content.utf8.count)
        byteBuffer.writeString(content)

        let config = try ConfigFileLoader.loadCredentials(from: byteBuffer, for: "user1", sourceProfile: nil)
        XCTAssertEqual(config.accessKey, "AKIAI44QH8DHBEXAMPLE")
        XCTAssertEqual(config.secretAccessKey, "je7MtGbClwBF/2Zp9Utk/h3yCo8nvbEXAMPLEKEY")
    }

    func testCredentialsWithSourceProfile() throws {
        let content = """
        [default]
        aws_access_key_id=AKIAIOSFODNN7EXAMPLE
        aws_secret_access_key=wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY

        [user1]
        role_arn = arn:aws:iam::123456789012:role/marketingadminrole
        source_profile = default
        role_session_name = foo@example.com
        """
        var byteBuffer = ByteBufferAllocator().buffer(capacity: content.utf8.count)
        byteBuffer.writeString(content)

        let config = try ConfigFileLoader.loadCredentials(from: byteBuffer, for: "user1", sourceProfile: nil)
        XCTAssertEqual(config.accessKey, "AKIAIOSFODNN7EXAMPLE")
        XCTAssertEqual(config.secretAccessKey, "wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY")
        XCTAssertEqual(config.roleArn, "arn:aws:iam::123456789012:role/marketingadminrole")
        XCTAssertEqual(config.sourceProfile, ConfigFileLoader.default)
    }

}
