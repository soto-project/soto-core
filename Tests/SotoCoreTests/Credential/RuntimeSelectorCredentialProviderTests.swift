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
    @Test func testSetupFail() async throws {
        let client = createAWSClient(credentialProvider: .selector(.custom { _ in NullCredentialProvider() }))
        try await withClient(client) {
            let error = await #expect(throws: CredentialProviderError.self) {
                _ = try await client.credentialProvider.getCredential(logger: TestEnvironment.logger)
            }
            #expect(error == .noProvider)

        }
    }

    @Test func testShutdown() async throws {
        let client = createAWSClient(credentialProvider: .selector(.environment, .configFile()))
        try await client.shutdown()
    }

    @Test func testFoundEmptyProvider() async throws {
        let provider: CredentialProviderFactory = .selector(.empty, .environment)
        let client = createAWSClient(credentialProvider: provider)
        try await withClient(client) {
            let credential = try await client.credentialProvider.getCredential(logger: TestEnvironment.logger)
            #expect(credential.accessKeyId == "")
            #expect(credential.secretAccessKey == "")
            #expect(credential.sessionToken == nil)
            let internalProvider = try await (client.credentialProvider as? RuntimeSelectorCredentialProvider)?.getCredentialProviderTask()
            #expect(internalProvider is EmptyCredentialProvider)
        }
    }

    @Test func testFoundSelectorWithOneProvider() async throws {
        let provider: CredentialProviderFactory = .selector(.empty)
        let client = createAWSClient(credentialProvider: provider)
        try await withClient(client) {
            let credential = try await client.credentialProvider.getCredential(logger: TestEnvironment.logger)
            #expect(credential.isEmpty())
            #expect(client.credentialProvider is EmptyCredentialProvider)
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
        try await withClient(client) {
            async let credentialTask = client.credentialProvider.getCredential(logger: TestEnvironment.logger)

            #expect(throws: Never.self) { try testServer.ec2MetadataServer(version: .v2) }

            let credential = try await credentialTask
            #expect(credential.accessKeyId == AWSTestServer.EC2InstanceMetaData.default.accessKeyId)
            #expect(credential.secretAccessKey == AWSTestServer.EC2InstanceMetaData.default.secretAccessKey)
            #expect(credential.sessionToken == AWSTestServer.EC2InstanceMetaData.default.token)
            let internalProvider = try await (client.credentialProvider as? RuntimeSelectorCredentialProvider)?.getCredentialProviderTask()
            #expect(internalProvider is RotatingCredentialProvider)
        }
    }

    @Test func testConfigFileProvider() async throws {
        let credentials = """
            [default]
            aws_access_key_id = AWSACCESSKEYID
            aws_secret_access_key = AWSSECRETACCESSKEY
            """
        let filename = "testConfigFileProvider-credentials"
        let filenameURL = URL(fileURLWithPath: filename)
        #expect(throws: Never.self) { try Data(credentials.utf8).write(to: filenameURL) }
        defer { #expect(throws: Never.self) { try FileManager.default.removeItem(at: filenameURL) } }

        let client = createAWSClient(credentialProvider: .selector(.configFile(credentialsFilePath: filename), .empty))
        try await withClient(client) {
            let credential = try await client.credentialProvider.getCredential(logger: TestEnvironment.logger)
            #expect(credential.accessKeyId == "AWSACCESSKEYID")
            #expect(credential.secretAccessKey == "AWSSECRETACCESSKEY")
            #expect(credential.sessionToken == nil)
            let internalProvider = try await (client.credentialProvider as? RuntimeSelectorCredentialProvider)?.getCredentialProviderTask()
            #expect(internalProvider is RotatingCredentialProvider)
        }
    }

    @Test func testConfigFileProviderFail() async throws {
        let client = createAWSClient(credentialProvider: .selector(.configFile(credentialsFilePath: "nonExistentCredentialFile"), .empty))
        try await withClient(client) {
            _ = try await client.credentialProvider.getCredential(logger: TestEnvironment.logger)
            let internalProvider = try await (client.credentialProvider as? RuntimeSelectorCredentialProvider)?.getCredentialProviderTask()
            #expect(internalProvider is EmptyCredentialProvider)
        }
    }

    @Suite(.serialized)
    struct Serialized {
    }
}
