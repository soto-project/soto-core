//===----------------------------------------------------------------------===//
//
// This source file is part of the Soto for AWS open source project
//
// Copyright (c) 2017-2026 the Soto project authors
// Licensed under Apache License v2.0
//
// See LICENSE.txt for license information
// See CONTRIBUTORS.txt for the list of Soto project authors
//
// SPDX-License-Identifier: Apache-2.0
//
//===----------------------------------------------------------------------===//

import Foundation
import Logging
import SotoTestUtils
import Testing

@testable import SotoCore

#if canImport(Glibc)
import Glibc
#elseif canImport(Musl)
import Musl
#elseif canImport(Darwin)
import Darwin.C
#elseif canImport(Android)
import Android
#else
#error("Unsupported platform")
#endif

extension Environment {
    static func set(_ value: String, for name: String) {
        guard setenv(name, value, 1) == 0 else {
            Issue.record("Failed to set environment")
            return
        }
    }

    static func unset(name: String) {
        #expect(unsetenv(name) == 0)
    }
}

/// Move all credential provider tests that change the credential environment variables into
/// one test suite that can be executed serially to avoid the tests conflicting with each other
@Suite(.serialized)
struct EnvironmentCredentialProviderTests {
    @Test func testSuccess() async throws {
        let accessKeyId = "AWSACCESSKEYID"
        let secretAccessKet = "AWSSECRETACCESSKEY"
        let sessionToken = "AWSSESSIONTOKEN"

        Environment.set(accessKeyId, for: "AWS_ACCESS_KEY_ID")
        Environment.set(secretAccessKet, for: "AWS_SECRET_ACCESS_KEY")
        Environment.set(sessionToken, for: "AWS_SESSION_TOKEN")
        defer {
            Environment.unset(name: "AWS_ACCESS_KEY_ID")
            Environment.unset(name: "AWS_SECRET_ACCESS_KEY")
            Environment.unset(name: "AWS_SESSION_TOKEN")
        }

        let staticCredentials = StaticCredentialProvider.fromEnvironment()
        let cred = try await staticCredentials?.getCredential(logger: .init(label: #function))

        #expect(cred?.accessKeyId == accessKeyId)
        #expect(cred?.secretAccessKey == secretAccessKet)
        #expect(cred?.sessionToken == sessionToken)
    }

    @Test func testFailWithoutAccessKeyId() {
        let secretAccessKet = "AWSSECRETACCESSKEY"
        let sessionToken = "AWSSESSIONTOKEN"

        Environment.set(secretAccessKet, for: "AWS_SECRET_ACCESS_KEY")
        Environment.set(sessionToken, for: "AWS_SESSION_TOKEN")
        defer {
            Environment.unset(name: "AWS_SECRET_ACCESS_KEY")
            Environment.unset(name: "AWS_SESSION_TOKEN")
        }

        let cred = StaticCredentialProvider.fromEnvironment()

        #expect(cred == nil)
    }

    @Test func testFailWithoutSecretAccessKey() {
        let accessKeyId = "AWSACCESSKEYID"
        let sessionToken = "AWSSESSIONTOKEN"

        Environment.set(accessKeyId, for: "AWS_ACCESS_KEY_ID")
        Environment.set(sessionToken, for: "AWS_SESSION_TOKEN")
        defer {
            Environment.unset(name: "AWS_ACCESS_KEY_ID")
            Environment.unset(name: "AWS_SESSION_TOKEN")
        }

        let cred = StaticCredentialProvider.fromEnvironment()

        #expect(cred == nil)
    }

    @Test func testSuccessWithoutSessionToken() async throws {
        let accessKeyId = "AWSACCESSKEYID"
        let secretAccessKet = "AWSSECRETACCESSKEY"

        Environment.set(accessKeyId, for: "AWS_ACCESS_KEY_ID")
        Environment.set(secretAccessKet, for: "AWS_SECRET_ACCESS_KEY")
        defer {
            Environment.unset(name: "AWS_ACCESS_KEY_ID")
            Environment.unset(name: "AWS_SECRET_ACCESS_KEY")
        }

        let staticCredentials = StaticCredentialProvider.fromEnvironment()
        let cred = try await staticCredentials?.getCredential(logger: .init(label: #function))

        #expect(cred?.accessKeyId == accessKeyId)
        #expect(cred?.secretAccessKey == secretAccessKet)
        #expect(cred?.sessionToken == nil)
    }

    @Test func testCredentialProviderSourceEnvironment() async throws {
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
            Environment.unset(name: "AWS_ACCESS_KEY_ID")
            Environment.unset(name: "AWS_SECRET_ACCESS_KEY")
        }
        let filename = #function
        let filenameURL = URL(fileURLWithPath: filename)
        #expect(throws: Never.self) { try Data(credentialsFile.utf8).write(to: filenameURL) }

        let httpClient = MockAWSHTTPClient { _ in fatalError() }
        let context = CredentialProviderFactory.Context(httpClient: httpClient, logger: TestEnvironment.logger, options: .init())

        defer {
            #expect(throws: Never.self) { try FileManager.default.removeItem(at: filenameURL) }
        }

        let sharedCredentials = try await ConfigFileLoader.loadSharedCredentials(
            credentialsFilePath: filename,
            configFilePath: "/dev/null",
            profile: profile
        )

        switch sharedCredentials {
        case .assumeRole(let aRoleArn, _, _, let sourceCredentialProvider):
            let credentials = try await sourceCredentialProvider.createProvider(context: context).getCredential(logger: context.logger)
            #expect(credentials.accessKeyId == accessKey)
            #expect(credentials.secretAccessKey == secretKey)
            #expect(aRoleArn == roleArn)
        default:
            Issue.record("Expected STS Assume Role")
        }
    }

    @Test func testAWSProfileConfigFile() async throws {
        let credentials = """
            [test-profile]
            aws_access_key_id = TESTPROFILE-AWSACCESSKEYID
            aws_secret_access_key = TESTPROFILE-AWSSECRETACCESSKEY
            """
        Environment.set("test-profile", for: "AWS_PROFILE")
        defer { Environment.unset(name: "AWS_PROFILE") }

        let filename = #function
        let filenameURL = URL(fileURLWithPath: filename)
        #expect(throws: Never.self) { try Data(credentials.utf8).write(to: filenameURL) }
        defer { #expect(throws: Never.self) { try FileManager.default.removeItem(at: filenameURL) } }

        let httpClient = MockAWSHTTPClient { _ in fatalError() }
        let factory = CredentialProviderFactory.configFile(credentialsFilePath: filenameURL.path)

        let provider = factory.createProvider(context: .init(httpClient: httpClient, logger: TestEnvironment.logger, options: .init()))

        let credential = try await provider.getCredential(logger: TestEnvironment.logger)
        #expect(credential.accessKeyId == "TESTPROFILE-AWSACCESSKEYID")
        #expect(credential.secretAccessKey == "TESTPROFILE-AWSSECRETACCESSKEY")
    }

    @Test func testFoundEnvironmentProvider() async throws {
        let accessKeyId = "AWSACCESSKEYID"
        let secretAccessKey = "AWSSECRETACCESSKEY"
        let sessionToken = "AWSSESSIONTOKEN"

        Environment.set(accessKeyId, for: "AWS_ACCESS_KEY_ID")
        Environment.set(secretAccessKey, for: "AWS_SECRET_ACCESS_KEY")
        Environment.set(sessionToken, for: "AWS_SESSION_TOKEN")
        defer {
            Environment.unset(name: "AWS_ACCESS_KEY_ID")
            Environment.unset(name: "AWS_SECRET_ACCESS_KEY")
            Environment.unset(name: "AWS_SESSION_TOKEN")
        }
        let client = createAWSClient(credentialProvider: .selector(.environment, .empty))
        try await withClient(client) {
            let credential = try await client.credentialProvider.getCredential(logger: TestEnvironment.logger)
            #expect(credential.accessKeyId == accessKeyId)
            #expect(credential.secretAccessKey == secretAccessKey)
            #expect(credential.sessionToken == sessionToken)
            let internalProvider = try await (client.credentialProvider as? RuntimeSelectorCredentialProvider)?.getCredentialProviderTask()
            #expect(internalProvider is StaticCredentialProvider)
        }
    }

    @Test func testEnvironmentProviderFail() async throws {
        Environment.unset(name: "AWS_ACCESS_KEY_ID")

        let provider: CredentialProviderFactory = .selector(.environment)
        let client = createAWSClient(credentialProvider: provider)
        try await withClient(client) {
            do {
                _ = try await client.credentialProvider.getCredential(logger: TestEnvironment.logger)
                Issue.record("Should not get here")
            } catch {
                #expect(error as? CredentialProviderError == CredentialProviderError.noProvider)
            }
        }
    }

    @Test func testECSProvider() async throws {
        Environment.unset(name: "AWS_ACCESS_KEY_ID")

        let testServer = AWSTestServer(serviceProtocol: .json)
        defer { #expect(throws: Never.self) { try testServer.stop() } }
        let path = "/" + UUID().uuidString
        Environment.set(path, for: ECSMetaDataClient.RelativeURIEnvironmentName)
        defer { Environment.unset(name: ECSMetaDataClient.RelativeURIEnvironmentName) }

        let customECS: CredentialProviderFactory = .custom { context in
            if let client = ECSMetaDataClient(httpClient: context.httpClient, host: testServer.address) {
                return RotatingCredentialProvider(context: context, provider: client)
            }
            // fallback
            return NullCredentialProvider()
        }
        let provider: CredentialProviderFactory = .selector(.environment, customECS, .empty)
        let client = createAWSClient(credentialProvider: provider)
        try await withClient(client) {
            async let credentialTask = client.credentialProvider.getCredential(logger: TestEnvironment.logger)

            #expect(throws: Never.self) { try testServer.ecsMetadataServer(path: path) }

            let credential = try await credentialTask
            #expect(credential.accessKeyId == AWSTestServer.ECSMetaData.default.accessKeyId)
            #expect(credential.secretAccessKey == AWSTestServer.ECSMetaData.default.secretAccessKey)
            #expect(credential.sessionToken == AWSTestServer.ECSMetaData.default.token)
            let internalProvider = try await (client.credentialProvider as? RuntimeSelectorCredentialProvider)?.getCredentialProviderTask()
            #expect(internalProvider is RotatingCredentialProvider)
        }
    }

    @Test func testECSProviderFail() async throws {
        Environment.unset(name: "AWS_ACCESS_KEY_ID")
        Environment.unset(name: ECSMetaDataClient.RelativeURIEnvironmentName)

        let provider: CredentialProviderFactory = .selector(.ecs)
        let client = createAWSClient(credentialProvider: provider)
        try await withClient(client) {
            let error = await #expect(throws: CredentialProviderError.self) {
                _ = try await client.credentialProvider.getCredential(logger: TestEnvironment.logger)
            }
            #expect(error == .noProvider)

        }
    }
}
