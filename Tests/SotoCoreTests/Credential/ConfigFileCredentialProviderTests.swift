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

    func testInternalSTSAssumeRoleProvider() throws {
        let credentials = STSCredentials(
            accessKeyId: "STSACCESSKEYID",
            expiration: Date(timeIntervalSince1970: 87_387_346),
            secretAccessKey: "STSSECRETACCESSKEY",
            sessionToken: "STSSESSIONTOKEN"
        )
        let testServer = AWSTestServer(serviceProtocol: .xml)
        defer { XCTAssertNoThrow(try testServer.stop()) }
        let client = AWSClient(
            credentialProvider: .internalSTSAssumeRole(
                request: .init(roleArn: "arn:aws:iam::000000000000:role/test-sts-assume-role", roleSessionName: "testInternalSTSAssumeRoleProvider"),
                credentialProvider: .empty,
                region: .useast1,
                endpoint: testServer.address
            ),
            httpClientProvider: .createNew,
            logger: TestEnvironment.logger
        )
        defer { XCTAssertNoThrow(try client.syncShutdown()) }

        XCTAssertNoThrow(try testServer.processRaw { _ in
            let output = STSAssumeRoleResponse(credentials: credentials)
            let xml = try XMLEncoder().encode(output)
            let byteBuffer = ByteBufferAllocator().buffer(string: xml.xmlString)
            let response = AWSTestServer.Response(httpStatus: .ok, headers: [:], body: byteBuffer)
            return .result(response)
        })
        var result: Credential?
        XCTAssertNoThrow(result = try client.credentialProvider.getCredential(on: client.eventLoopGroup.next(), logger: AWSClient.loggingDisabled).wait())
        let stsCredentials = result as? STSCredentials
        XCTAssertEqual(stsCredentials?.accessKeyId, credentials.accessKeyId)
        XCTAssertEqual(stsCredentials?.expiration, credentials.expiration)
        XCTAssertEqual(stsCredentials?.secretAccessKey, credentials.secretAccessKey)
        XCTAssertEqual(stsCredentials?.sessionToken, credentials.sessionToken)
    }
}

// Extend STSAssumeRoleRequest so it can be used with the AWSTestServer
extension STSAssumeRoleRequest: Decodable {
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let roleArn = try container.decode(String.self, forKey: .roleArn)
        let roleSessionName = try container.decode(String.self, forKey: .roleSessionName)
        self.init(roleArn: roleArn, roleSessionName: roleSessionName)
    }

    private enum CodingKeys: String, CodingKey {
        case roleArn = "RoleArn"
        case roleSessionName = "RoleSessionName"
    }
}

// Extend STSAssumeRoleResponse so it can be used with the AWSTestServer
extension STSAssumeRoleResponse: Encodable {
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(credentials, forKey: .credentials)
    }

    private enum CodingKeys: String, CodingKey {
        case credentials = "Credentials"
    }
}

// Extend STSCredentials so it can be used with the AWSTestServer
extension STSCredentials: Encodable {
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(accessKeyId, forKey: .accessKeyId)
        try container.encode(expiration, forKey: .expiration)
        try container.encode(secretAccessKey, forKey: .secretAccessKey)
        try container.encode(sessionToken, forKey: .sessionToken)
    }

    private enum CodingKeys: String, CodingKey {
        case accessKeyId = "AccessKeyId"
        case expiration = "Expiration"
        case secretAccessKey = "SecretAccessKey"
        case sessionToken = "SessionToken"
    }
}
