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
import Logging
import NIOCore
import NIOPosix
import SotoTestUtils
import Testing

@testable import SotoCore

@Suite(.serialized)
struct MetaDataCredentialProviderTests {
    // MARK: - ECSMetaDataClient -

    @Test func testECSMetaDataClient() async throws {
        let path = "/" + UUID().uuidString
        Environment.set(path, for: ECSMetaDataClient.RelativeURIEnvironmentName)
        defer { Environment.unset(name: ECSMetaDataClient.RelativeURIEnvironmentName) }

        let client = ECSMetaDataClient(httpClient: MockHTTPClient.ecsMetadataServer(path: path), host: "http://localhost:8080")
        let metaData = try await client!.getMetaData(logger: TestEnvironment.logger)

        #expect(metaData.accessKeyId == MockHTTPClient.ECSMetaData.default.accessKeyId)
        #expect(metaData.secretAccessKey == MockHTTPClient.ECSMetaData.default.secretAccessKey)
        #expect(metaData.token == MockHTTPClient.ECSMetaData.default.token)
        #expect(abs(metaData.expiration.timeIntervalSinceNow - MockHTTPClient.ECSMetaData.default.expiration.timeIntervalSinceNow) < 1.0)
        #expect(metaData.roleArn == MockHTTPClient.ECSMetaData.default.roleArn)
    }

    @Test func testECSMetaDataClientDefaultHost() {
        #expect(ECSMetaDataClient.Host == "http://169.254.170.2")
        #expect(ECSMetaDataClient.RelativeURIEnvironmentName == "AWS_CONTAINER_CREDENTIALS_RELATIVE_URI")
    }

    @Test func testECSMetaDataClientIsNotCreatedWithoutEnvVariable() {
        Environment.unset(name: ECSMetaDataClient.RelativeURIEnvironmentName)
        #expect(ECSMetaDataClient(httpClient: MockHTTPClient.ecsMetadataServer(path: "/"), host: "http://localhost") == nil)
    }

    // MARK: - InstanceMetaDataClient -

    @Test func testEC2InstanceMetaDataClientUsingVersion2() async throws {
        let path = "/" + UUID().uuidString
        Environment.set(path, for: ECSMetaDataClient.RelativeURIEnvironmentName)
        defer { Environment.unset(name: ECSMetaDataClient.RelativeURIEnvironmentName) }

        let client = InstanceMetaDataClient(httpClient: MockHTTPClient.ec2MetadataServer(version: .v2), host: "http://localhost:8080")
        let metaData = try await client.getMetaData(logger: TestEnvironment.logger)

        #expect(metaData.accessKeyId == MockHTTPClient.EC2InstanceMetaData.default.accessKeyId)
        #expect(metaData.secretAccessKey == MockHTTPClient.EC2InstanceMetaData.default.secretAccessKey)
        #expect(metaData.token == MockHTTPClient.EC2InstanceMetaData.default.token)
        #expect(
            abs(metaData.expiration.timeIntervalSinceNow - MockHTTPClient.EC2InstanceMetaData.default.expiration.timeIntervalSinceNow) < 1.0
        )
        #expect(metaData.code == MockHTTPClient.EC2InstanceMetaData.default.code)
        #expect(metaData.lastUpdated == MockHTTPClient.EC2InstanceMetaData.default.lastUpdated)
        #expect(metaData.type == MockHTTPClient.EC2InstanceMetaData.default.type)
    }

    @Test func testEC2InstanceMetaDataClientUsingVersion1() async throws {
        let client = InstanceMetaDataClient(httpClient: MockHTTPClient.ec2MetadataServer(version: .v1), host: "http://localhost:8080")
        let metaData = try await client.getMetaData(logger: TestEnvironment.logger)

        #expect(metaData.accessKeyId == MockHTTPClient.EC2InstanceMetaData.default.accessKeyId)
        #expect(metaData.secretAccessKey == MockHTTPClient.EC2InstanceMetaData.default.secretAccessKey)
        #expect(metaData.token == MockHTTPClient.EC2InstanceMetaData.default.token)
        #expect(
            abs(metaData.expiration.timeIntervalSinceNow - MockHTTPClient.EC2InstanceMetaData.default.expiration.timeIntervalSinceNow) < 1.0
        )
        #expect(metaData.code == MockHTTPClient.EC2InstanceMetaData.default.code)
        #expect(metaData.lastUpdated == MockHTTPClient.EC2InstanceMetaData.default.lastUpdated)
        #expect(metaData.type == MockHTTPClient.EC2InstanceMetaData.default.type)
    }

    @Test func testEC2UInstanceMetaDataClientDefaultHost() {
        #expect(InstanceMetaDataClient.Host == "http://169.254.169.254")
    }

    @Test func testEC2RotatingCredentialProviderShutdown() async throws {
        let customEC2: CredentialProviderFactory = .custom { context in
            let client = InstanceMetaDataClient(httpClient: context.httpClient)
            return RotatingCredentialProvider(context: context, provider: client)
        }

        let client = createAWSClient(credentialProvider: customEC2, httpClient: MockHTTPClient.ec2MetadataServer(version: .v2))
        try await withClient(client) {
            let credential = try await client.credentialProvider.getCredential(logger: .current)
            #expect(credential.accessKeyId == MockHTTPClient.EC2InstanceMetaData.default.accessKeyId)
            #expect(credential.secretAccessKey == MockHTTPClient.EC2InstanceMetaData.default.secretAccessKey)
            #expect(credential.sessionToken == MockHTTPClient.EC2InstanceMetaData.default.token)
            #expect(
                abs(credential.expiration.timeIntervalSinceNow - MockHTTPClient.EC2InstanceMetaData.default.expiration.timeIntervalSinceNow) < 1.0
            )
        }
    }
}
