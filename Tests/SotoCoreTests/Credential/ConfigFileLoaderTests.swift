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

        let config = try ConfigFileLoader.parseProfileConfig(from: byteBuffer, for: ConfigFileLoader.defaultProfile)
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

        let config = try ConfigFileLoader.parseProfileConfig(from: byteBuffer, for: "marketingadmin")
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

        let config = try ConfigFileLoader.parseProfileConfig(from: byteBuffer, for: "marketingadmin")
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

        let config = try ConfigFileLoader.parseProfileConfig(from: byteBuffer, for: "marketingadmin")
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

        let config = try ConfigFileLoader.parseProfileConfig(from: byteBuffer, for: "marketingadmin")
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

        let config = try ConfigFileLoader.parseCredentials(from: byteBuffer, for: ConfigFileLoader.defaultProfile, sourceProfile: nil)
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

        let config = try ConfigFileLoader.parseCredentials(from: byteBuffer, for: "user1", sourceProfile: nil)
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

        let config = try ConfigFileLoader.parseCredentials(from: byteBuffer, for: "user1", sourceProfile: nil)
        XCTAssertEqual(config.accessKey, "AKIAIOSFODNN7EXAMPLE")
        XCTAssertEqual(config.secretAccessKey, "wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY")
        XCTAssertEqual(config.roleArn, "arn:aws:iam::123456789012:role/marketingadminrole")
        XCTAssertEqual(config.sourceProfile, ConfigFileLoader.defaultProfile)
    }

    // MARK: - Config file path expansion

    func testExpandTildeInFilePath() {
        let expandableFilePath = "~/.aws/credentials"
        let expandedNewPath = ConfigFileLoader.expandTildeInFilePath(expandableFilePath)

        #if os(Linux)
        XCTAssert(!expandedNewPath.hasPrefix("~"))
        #else

        #if os(macOS)
        // on macOS, we want to be sure the expansion produces the posix $HOME and
        // not the sanboxed home $HOME/Library/Containers/<bundle-id>/Data
        let macOSHomePrefix = "/Users/"
        XCTAssert(expandedNewPath.starts(with: macOSHomePrefix))
        XCTAssert(!expandedNewPath.contains("/Library/Containers/"))
        #endif

        // this doesn't work on linux because of SR-12843
        let expandedNSString = NSString(string: expandableFilePath).expandingTildeInPath
        XCTAssertEqual(expandedNewPath, expandedNSString)
        #endif

        let unexpandableFilePath = "/.aws/credentials"
        let unexpandedNewPath = ConfigFileLoader.expandTildeInFilePath(unexpandableFilePath)
        let unexpandedNSString = NSString(string: unexpandableFilePath).expandingTildeInPath

        XCTAssertEqual(unexpandedNewPath, unexpandedNSString)
        XCTAssertEqual(unexpandedNewPath, unexpandableFilePath)
    }
}
