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

import AsyncHTTPClient
import HTTPTypes
import Logging
import NIOCore
import NIOHTTP1
import NIOPosix
import SotoTestUtils
import SotoXML
import Testing

@testable import SotoCore

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif

struct ConfigFileCredentialProviderTests {
    // MARK: - Credential Provider

    func makeContext() -> CredentialProviderFactory.Context {
        let httpClient = MockAWSHTTPClient { _ in fatalError() }
        return .init(httpClient: httpClient, logger: TestEnvironment.logger, options: .init())
    }

    @Test func testCredentialProviderStatic() async throws {
        let credentials = ConfigFileLoader.SharedCredentials.staticCredential(
            accessKeyId: "foo",
            secretAccessKey: "bar"
        )
        let context = self.makeContext()

        let provider = try ConfigFileCredentialProvider.credentialProvider(
            from: credentials,
            context: context,
            endpoint: nil,
            retryPolicy: .default
        )
        #expect((provider as? StaticCredentialProvider)?.credential.accessKeyId == "foo")
        #expect((provider as? StaticCredentialProvider)?.credential.secretAccessKey == "bar")

        try await provider.shutdown()
    }

    @Test func testCredentialProviderSTSAssumeRole() async throws {
        let credentials = ConfigFileLoader.SharedCredentials.assumeRole(
            roleArn: "arn",
            sessionName: "baz",
            region: nil,
            sourceCredentialProvider: .static(accessKeyId: "foo", secretAccessKey: "bar")
        )
        let context = self.makeContext()

        let provider = try ConfigFileCredentialProvider.credentialProvider(
            from: credentials,
            context: context,
            endpoint: nil,
            retryPolicy: .default
        )
        let stsProvider = try #require(provider as? STSAssumeRoleCredentialProvider)
        switch stsProvider.request {
        case .assumeRole(let arn, let sessionName):
            #expect(arn == "arn")
            #expect(sessionName == "baz")
        default: Issue.record()
        }

        try await provider.shutdown()
    }

    @Test func testProfileScopedProviderWrapsErrorWithProfileName() async throws {
        // Direct unit test for the wrapper: any error from the inner provider must surface as
        // a `ProfileCredentialError` whose description includes the profile name and whose
        // `underlying` preserves the original error.
        struct StubError: Error, Equatable {}
        struct ThrowingProvider: CredentialProvider {
            func getCredential(logger: Logger) async throws -> Credential { throw StubError() }
        }
        let wrapped = ProfileScopedCredentialProvider(inner: ThrowingProvider(), profile: "dev")

        do {
            _ = try await wrapped.getCredential(logger: TestEnvironment.logger)
            Issue.record("Expected ProfileCredentialError")
        } catch let error as ProfileCredentialError {
            #expect(error.profile == "dev")
            #expect(error.underlying is StubError)
            #expect(error.description.contains("dev"), "Description should name the profile: \(error.description)")
        } catch {
            Issue.record("Expected ProfileCredentialError, got \(error)")
        }
    }

    @Test func testCredentialProviderTagsErrorsWithProfileFromFile() async throws {
        // Integration check: loading via the file overload must produce a `ProfileScopedCredentialProvider`
        // bound to the requested profile, so any failure from inside the chain surfaces with that profile.
        let profile = "dev"
        let credentialsFile = """
            [\(profile)]
            aws_access_key_id = AKIAIOSFODNN7EXAMPLE
            aws_secret_access_key = wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY
            """
        let credentialsPath = "creds-\(UUID().uuidString)"
        try credentialsFile.write(toFile: credentialsPath, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(atPath: credentialsPath) }
        let context = self.makeContext()

        let provider = try await ConfigFileCredentialProvider.credentialProvider(
            from: credentialsPath,
            configFilePath: "/dev/null",
            for: profile,
            context: context,
            endpoint: nil,
            retryPolicy: .default
        )

        let scoped = try #require(provider as? ProfileScopedCredentialProvider)
        #expect(scoped.profile == profile)

        try await provider.shutdown()
    }

    // MARK: - Config File Credentials Provider

    @Test func testConfigFileSuccess() async throws {
        let credentials = """
            [default]
            aws_access_key_id = AWSACCESSKEYID
            aws_secret_access_key = AWSSECRETACCESSKEY
            """
        let filename = #function
        let filenameURL = URL(fileURLWithPath: filename)
        #expect(throws: Never.self) { try Data(credentials.utf8).write(to: filenameURL) }
        defer {
            #expect(throws: Never.self) {
                try FileManager.default.removeItem(at: filenameURL)
            }
        }

        let httpClient = MockAWSHTTPClient { _ in fatalError() }
        let factory = CredentialProviderFactory.configFile(credentialsFilePath: filenameURL.path)

        let provider = factory.createProvider(context: .init(httpClient: httpClient, logger: TestEnvironment.logger, options: .init()))

        let credential = try await provider.getCredential(logger: TestEnvironment.logger)
        #expect(credential.accessKeyId == "AWSACCESSKEYID")
        #expect(credential.secretAccessKey == "AWSSECRETACCESSKEY")
    }

    @Test func testConfigFileNotAvailable() async {
        let credentialsFilename = "credentials_\(#function)"
        let credentialsFilenameURL = URL(fileURLWithPath: credentialsFilename)

        let configFilename = "config_\(#function)"
        let configFilenameURL = URL(fileURLWithPath: configFilename)

        let httpClient = MockAWSHTTPClient { _ in fatalError() }

        let factory = CredentialProviderFactory.configFile(
            credentialsFilePath: credentialsFilenameURL.path,
            configFilePath: configFilenameURL.path,
        )

        let provider = factory.createProvider(context: .init(httpClient: httpClient, logger: TestEnvironment.logger, options: .init()))

        do {
            _ = try await provider.getCredential(logger: TestEnvironment.logger)
            Issue.record("Should throw error")
        } catch {
            #expect(error as? CredentialProviderError == .noProvider)
        }
    }

    @Test func testConfigFileShutdown() {
        let client = createAWSClient(credentialProvider: .configFile())
        #expect(throws: Never.self) { try client.syncShutdown() }
    }

    // MARK: - Role ARN Credential

    @Test func testRoleARNSourceProfile() async throws {
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

        // Prepare mock HTTP client
        let httpClient = MockAWSHTTPClient { request in
            let output = STSAssumeRoleResponse(credentials: stsCredentials)
            let xml = try XMLEncoder().encode(output)
            let byteBuffer = xml.map { ByteBuffer(string: $0.xmlString) } ?? .init()
            return .init(response: .init(status: .ok), body: .init(buffer: byteBuffer))
        }
        // Here we use `.custom` provider factory, since we need to inject the testServer endpoint
        let client = createAWSClient(
            credentialProvider: .custom { context -> any CredentialProvider in
                ConfigFileCredentialProvider(
                    credentialsFilePath: credentialsFilePath,
                    configFilePath: configFilePath,
                    profile: profile,
                    context: context,
                    retryPolicy: .default
                )
            },
            httpClient: httpClient
        )
        defer { #expect(throws: Never.self) { try client.syncShutdown() } }

        // Retrieve credentials
        async let futureCredentials = client.credentialProvider.getCredential(
            logger: TestEnvironment.logger
        )

        let credentials = try await futureCredentials

        // Verify credentials match those returned from STS Assume Role operation
        #expect(credentials.accessKeyId == stsCredentials.accessKeyId)
        #expect(credentials.secretAccessKey == stsCredentials.secretAccessKey)
    }

    @Suite(.serialized)
    struct Serialized {
    }
}
