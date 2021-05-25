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
import struct Foundation.UUID
import NIO
@testable import SotoCore
import SotoTestUtils
import SotoXML
import XCTest

class ConfigFileCredentialProviderTests: XCTestCase {
    // MARK: - Credential Provider

    func makeContext() -> (CredentialProviderFactory.Context, MultiThreadedEventLoopGroup, HTTPClient) {
        let eventLoopGroup = MultiThreadedEventLoopGroup(numberOfThreads: 1)
        let eventLoop = eventLoopGroup.next()
        let httpClient = HTTPClient(eventLoopGroupProvider: .shared(eventLoop))
        return (.init(httpClient: httpClient, eventLoop: eventLoop, context: TestEnvironment.loggingContext, options: .init()), eventLoopGroup, httpClient)
    }

    func testCredentialProviderStatic() {
        let credentials = ConfigFileLoader.SharedCredentials.staticCredential(credential: StaticCredential(accessKeyId: "foo", secretAccessKey: "bar"))
        let (context, eventLoopGroup, httpClient) = self.makeContext()

        let provider = try? ConfigFileCredentialProvider.credentialProvider(
            from: credentials,
            context: context,
            endpoint: nil
        )
        XCTAssertEqual((provider as? StaticCredential)?.accessKeyId, "foo")
        XCTAssertEqual((provider as? StaticCredential)?.secretAccessKey, "bar")

        XCTAssertNoThrow(try provider?.shutdown(on: context.eventLoop).wait())
        XCTAssertNoThrow(try httpClient.syncShutdown())
        XCTAssertNoThrow(try eventLoopGroup.syncShutdownGracefully())
    }

    func testCredentialProviderSTSAssumeRole() {
        let credentials = ConfigFileLoader.SharedCredentials.assumeRole(
            roleArn: "arn",
            sessionName: "baz",
            region: nil,
            sourceCredentialProvider: .static(accessKeyId: "foo", secretAccessKey: "bar")
        )
        let (context, eventLoopGroup, httpClient) = self.makeContext()

        let provider = try? ConfigFileCredentialProvider.credentialProvider(
            from: credentials,
            context: context,
            endpoint: nil
        )
        XCTAssertTrue(provider is STSAssumeRoleCredentialProvider)
        XCTAssertEqual((provider as? STSAssumeRoleCredentialProvider)?.request.roleArn, "arn")

        XCTAssertNoThrow(try provider?.shutdown(on: context.eventLoop).wait())
        XCTAssertNoThrow(try httpClient.syncShutdown())
        XCTAssertNoThrow(try eventLoopGroup.syncShutdownGracefully())
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

        let provider = factory.createProvider(context: .init(httpClient: httpClient, eventLoop: eventLoop, context: TestEnvironment.loggingContext, options: .init()))

        var credential: Credential?
        XCTAssertNoThrow(credential = try provider.getCredential(on: eventLoop, context: TestEnvironment.loggingContext).wait())
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

        let provider = factory.createProvider(context: .init(httpClient: httpClient, eventLoop: eventLoop, context: TestEnvironment.loggingContext, options: .init()))

        var credential: Credential?
        XCTAssertNoThrow(credential = try provider.getCredential(on: eventLoop, context: TestEnvironment.loggingContext).wait())
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

        let provider = factory.createProvider(context: .init(httpClient: httpClient, eventLoop: eventLoop, context: TestEnvironment.loggingContext, options: .init()))

        XCTAssertThrowsError(_ = try provider.getCredential(on: eventLoop, context: TestEnvironment.loggingContext).wait()) { error in
            print("\(error)")
            XCTAssertEqual(error as? CredentialProviderError, .noProvider)
        }
    }

    func testCredentialProviderSourceEnvironment() throws {
        let accessKey = "AKIAIOSFODNN7EXAMPLE"
        let secretKey = "wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY"
        let profile = "marketingadmin"
        let roleArn = "arn:aws:iam::123456789012:role/marketingadminrole"
        let credentialsFile = """
        [\(profile)]
        role_arn = \(roleArn)
        credential_source = Environment
        """

        Environment.set(accessKey, for: "AWS_ACCESS_KEY_ID")
        Environment.set(secretKey, for: "AWS_SECRET_ACCESS_KEY")
        defer {
            Environment.unset(name: accessKey)
            Environment.unset(name: secretKey)
        }
        let filename = "credentials"
        let filenameURL = URL(fileURLWithPath: filename)
        XCTAssertNoThrow(try Data(credentialsFile.utf8).write(to: filenameURL))
        let (context, eventLoopGroup, httpClient) = makeContext()

        defer {
            XCTAssertNoThrow(try FileManager.default.removeItem(at: filenameURL))
            XCTAssertNoThrow(try httpClient.syncShutdown())
            XCTAssertNoThrow(try eventLoopGroup.syncShutdownGracefully())
        }

        let sharedCredentials = try ConfigFileLoader.loadSharedCredentials(
            credentialsFilePath: filename,
            configFilePath: "/dev/null",
            profile: profile,
            context: context
        ).wait()

        switch sharedCredentials {
        case .assumeRole(let aRoleArn, _, _, let sourceCredentialProvider):
            let credentials = try sourceCredentialProvider.createProvider(context: context).getCredential(on: context.eventLoop, context: context.context).wait()
            XCTAssertEqual(credentials.accessKeyId, accessKey)
            XCTAssertEqual(credentials.secretAccessKey, secretKey)
            XCTAssertEqual(aRoleArn, roleArn)
        default:
            XCTFail("Expected STS Assume Role")
        }
    }

    func testConfigFileShutdown() {
        let client = createAWSClient(credentialProvider: .configFile())
        XCTAssertNoThrow(try client.syncShutdown())
    }

    // MARK: - Role ARN Credential

    func testRoleARNSourceProfile() throws {
        let profile = "user1"

        // Prepare mock STSAssumeRole credentials
        let stsCredentials = STSCredentials(
            accessKeyId: "STSACCESSKEYID",
            expiration: Date.distantFuture,
            secretAccessKey: "STSSECRETACCESSKEY",
            sessionToken: "STSSESSIONTOKEN"
        )

        // Prepare credentials file
        let credentialsFile = """
        [default]
        aws_access_key_id = DEFAULTACCESSKEY
        aws_secret_access_key=DEFAULTSECRETACCESSKEY
        aws_session_token =TOKENFOO

        [\(profile)]
        role_arn       = arn:aws:iam::000000000000:role/test-sts-assume-role
        source_profile = default
        color          = ff0000
        """
        let credentialsFilePath = "credentials-" + UUID().uuidString
        try credentialsFile.write(toFile: credentialsFilePath, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(atPath: credentialsFilePath) }

        // Prepare config file
        let configFile = """
        region=us-west-2
        role_session_name =testRoleARNSourceProfile
        """
        let configFilePath = "config-" + UUID().uuidString
        try configFile.write(toFile: configFilePath, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(atPath: configFilePath) }

        // Prepare test server and AWS client
        let testServer = AWSTestServer(serviceProtocol: .xml)
        defer { XCTAssertNoThrow(try testServer.stop()) }
        let httpClient = HTTPClient(eventLoopGroupProvider: .createNew)
        defer { XCTAssertNoThrow(try httpClient.syncShutdown()) }

        // Here we use `.custom` provider factory, since we need to inject the testServer endpoint
        let client = createAWSClient(credentialProvider: .custom { context -> CredentialProvider in
            ConfigFileCredentialProvider(
                credentialsFilePath: credentialsFilePath,
                configFilePath: configFilePath,
                profile: profile,
                context: context,
                endpoint: testServer.address
            )
        }, httpClientProvider: .shared(httpClient))
        defer { XCTAssertNoThrow(try client.syncShutdown()) }

        // Retrieve credentials
        let futureCredentials = client.credentialProvider.getCredential(
            on: client.eventLoopGroup.next(),
            context: TestEnvironment.loggingContext
        )
        try testServer.processRaw { _ in
            let output = STSAssumeRoleResponse(credentials: stsCredentials)
            let xml = try XMLEncoder().encode(output)
            let byteBuffer = ByteBufferAllocator().buffer(string: xml.xmlString)
            let response = AWSTestServer.Response(httpStatus: .ok, headers: [:], body: byteBuffer)
            return .result(response)
        }
        let credentials = try futureCredentials.wait()

        // Verify credentials match those returned from STS Assume Role operation
        XCTAssertEqual(credentials.accessKeyId, stsCredentials.accessKeyId)
        XCTAssertEqual(credentials.secretAccessKey, stsCredentials.secretAccessKey)
    }
}
