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

import Foundation
import NIOCore
import SotoTestUtils
import Testing

@testable import SotoCore

struct RuntimeSelectorCredentialProviderTests {
    @Test func testSetupFail() async {
        let client = createAWSClient(credentialProvider: .selector(.custom { _ in NullCredentialProvider() }))
        defer { #expect(throws: Never.self) { try client.syncShutdown() } }
        do {
            _ = try await client.credentialProvider.getCredential(logger: TestEnvironment.logger)
            Issue.record("Shouldn't get here")
        } catch {
            #expect(error as? CredentialProviderError == CredentialProviderError.noProvider)
        }
    }

    @Test func testShutdown() async throws {
        let client = createAWSClient(credentialProvider: .selector(.environment, .configFile()))
        try await client.shutdown()
    }

    @Test func testFoundEnvironmentProvider() async throws {
        let accessKeyId = "AWSACCESSKEYID"
        let secretAccessKey = "AWSSECRETACCESSKEY"
        let sessionToken = "AWSSESSIONTOKEN"

        Environment.set(accessKeyId, for: "AWS_ACCESS_KEY_ID")
        Environment.set(secretAccessKey, for: "AWS_SECRET_ACCESS_KEY")
        Environment.set(sessionToken, for: "AWS_SESSION_TOKEN")

        let client = createAWSClient(credentialProvider: .selector(.environment, .empty))
        defer { #expect(throws: Never.self) { try client.syncShutdown() } }
        let credential = try await client.credentialProvider.getCredential(logger: TestEnvironment.logger)
        #expect(credential.accessKeyId == accessKeyId)
        #expect(credential.secretAccessKey == secretAccessKey)
        #expect(credential.sessionToken == sessionToken)
        let internalProvider = try await (client.credentialProvider as? RuntimeSelectorCredentialProvider)?.getCredentialProviderTask()
        #expect(internalProvider is StaticCredentialProvider)

        Environment.unset(name: "AWS_ACCESS_KEY_ID")
        Environment.unset(name: "AWS_SECRET_ACCESS_KEY")
        Environment.unset(name: "AWS_SESSION_TOKEN")
    }

    @Test func testEnvironmentProviderFail() async throws {
        Environment.unset(name: "AWS_ACCESS_KEY_ID")

        let provider: CredentialProviderFactory = .selector(.environment)
        let client = createAWSClient(credentialProvider: provider)
        defer { #expect(throws: Never.self) { try client.syncShutdown() } }
        do {
            _ = try await client.credentialProvider.getCredential(logger: TestEnvironment.logger)
            Issue.record("Should not get here")
        } catch {
            #expect(error as? CredentialProviderError == CredentialProviderError.noProvider)
        }
    }

    @Test func testFoundEmptyProvider() async throws {
        let provider: CredentialProviderFactory = .selector(.empty, .environment)
        let client = createAWSClient(credentialProvider: provider)
        defer { #expect(throws: Never.self) { try client.syncShutdown() } }
        let credential = try await client.credentialProvider.getCredential(logger: TestEnvironment.logger)
        #expect(credential.accessKeyId == "")
        #expect(credential.secretAccessKey == "")
        #expect(credential.sessionToken == nil)
        let internalProvider = try await (client.credentialProvider as? RuntimeSelectorCredentialProvider)?.getCredentialProviderTask()
        #expect(internalProvider is EmptyCredentialProvider)
    }

    @Test func testFoundSelectorWithOneProvider() async throws {
        let provider: CredentialProviderFactory = .selector(.empty)
        let client = createAWSClient(credentialProvider: provider)
        defer { #expect(throws: Never.self) { try client.syncShutdown() } }
        let credential = try await client.credentialProvider.getCredential(logger: TestEnvironment.logger)
        #expect(credential.isEmpty())
        #expect(client.credentialProvider is EmptyCredentialProvider)
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
        defer { #expect(throws: Never.self) { try client.syncShutdown() } }

        async let credentialTask = client.credentialProvider.getCredential(logger: TestEnvironment.logger)

        #expect(throws: Never.self) { try testServer.ecsMetadataServer(path: path) }

        let credential = try await credentialTask
        #expect(credential.accessKeyId == AWSTestServer.ECSMetaData.default.accessKeyId)
        #expect(credential.secretAccessKey == AWSTestServer.ECSMetaData.default.secretAccessKey)
        #expect(credential.sessionToken == AWSTestServer.ECSMetaData.default.token)
        let internalProvider = try await (client.credentialProvider as? RuntimeSelectorCredentialProvider)?.getCredentialProviderTask()
        #expect(internalProvider is RotatingCredentialProvider)
    }

    @Test func testECSProviderFail() async {
        Environment.unset(name: "AWS_ACCESS_KEY_ID")
        Environment.unset(name: ECSMetaDataClient.RelativeURIEnvironmentName)

        let provider: CredentialProviderFactory = .selector(.ecs)
        let client = createAWSClient(credentialProvider: provider)
        defer { #expect(throws: Never.self) { try client.syncShutdown() } }
        do {
            _ = try await client.credentialProvider.getCredential(logger: TestEnvironment.logger)
            Issue.record("Should not get here")
        } catch {
            #expect(error as? CredentialProviderError == .noProvider)
        }
    }

    @Test func testEC2Provider() async throws {
        let testServer = AWSTestServer(serviceProtocol: .json)
        defer { #expect(throws: Never.self) { try testServer.stop() } }
        let customEC2: CredentialProviderFactory = .custom { context in
            let client = InstanceMetaDataClient(httpClient: context.httpClient, host: testServer.address)
            return RotatingCredentialProvider(context: context, provider: client)
        }

        let client = createAWSClient(credentialProvider: .selector(customEC2, .empty))
        defer { #expect(throws: Never.self) { try client.syncShutdown() } }
        async let credentialTask = client.credentialProvider.getCredential(logger: TestEnvironment.logger)

        #expect(throws: Never.self) { try testServer.ec2MetadataServer(version: .v2) }

        let credential = try await credentialTask
        #expect(credential.accessKeyId == AWSTestServer.EC2InstanceMetaData.default.accessKeyId)
        #expect(credential.secretAccessKey == AWSTestServer.EC2InstanceMetaData.default.secretAccessKey)
        #expect(credential.sessionToken == AWSTestServer.EC2InstanceMetaData.default.token)
        let internalProvider = try await (client.credentialProvider as? RuntimeSelectorCredentialProvider)?.getCredentialProviderTask()
        #expect(internalProvider is RotatingCredentialProvider)
    }

    @Test func testConfigFileProvider() async throws {
        let credentials = """
            [default]
            aws_access_key_id = AWSACCESSKEYID
            aws_secret_access_key = AWSSECRETACCESSKEY
            """
        let filename = "credentials"
        let filenameURL = URL(fileURLWithPath: filename)
        #expect(throws: Never.self) { try Data(credentials.utf8).write(to: filenameURL) }
        defer { #expect(throws: Never.self) { try FileManager.default.removeItem(at: filenameURL) } }

        let client = createAWSClient(credentialProvider: .selector(.configFile(credentialsFilePath: filename), .empty))
        defer { #expect(throws: Never.self) { try client.syncShutdown() } }
        let credential = try await client.credentialProvider.getCredential(logger: TestEnvironment.logger)
        #expect(credential.accessKeyId == "AWSACCESSKEYID")
        #expect(credential.secretAccessKey == "AWSSECRETACCESSKEY")
        #expect(credential.sessionToken == nil)
        let internalProvider = try await (client.credentialProvider as? RuntimeSelectorCredentialProvider)?.getCredentialProviderTask()
        #expect(internalProvider is RotatingCredentialProvider)
    }

    @Test func testConfigFileProviderFail() async throws {
        let client = createAWSClient(credentialProvider: .selector(.configFile(credentialsFilePath: "nonExistentCredentialFile"), .empty))
        defer { #expect(throws: Never.self) { try client.syncShutdown() } }
        _ = try await client.credentialProvider.getCredential(logger: TestEnvironment.logger)
        let internalProvider = try await (client.credentialProvider as? RuntimeSelectorCredentialProvider)?.getCredentialProviderTask()
        #expect(internalProvider is EmptyCredentialProvider)
    }
}
