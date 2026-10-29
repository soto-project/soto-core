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

import Logging
import NIOCore
import NIOPosix
import SotoTestUtils
import XCTest

@testable import SotoCore

class MetaDataCredentialProviderTests: XCTestCase {
    // MARK: - ECSMetaDataClient -

    func testECSMetaDataClient() async throws {
        let path = "/" + UUID().uuidString
        Environment.set(path, for: ECSMetaDataClient.RelativeURIEnvironmentName)
        defer { Environment.unset(name: ECSMetaDataClient.RelativeURIEnvironmentName) }

        let client = ECSMetaDataClient(httpClient: MockHTTPClient.ecsMetadataServer(path: path), host: "http://localhost:8080")
        let metaData = try await client!.getMetaData(logger: TestEnvironment.logger)

        XCTAssertEqual(metaData.accessKeyId, MockHTTPClient.ECSMetaData.default.accessKeyId)
        XCTAssertEqual(metaData.secretAccessKey, MockHTTPClient.ECSMetaData.default.secretAccessKey)
        XCTAssertEqual(metaData.token, MockHTTPClient.ECSMetaData.default.token)
        XCTAssertEqual(metaData.expiration.timeIntervalSinceNow, MockHTTPClient.ECSMetaData.default.expiration.timeIntervalSinceNow, accuracy: 1.0)
        XCTAssertEqual(metaData.roleArn, MockHTTPClient.ECSMetaData.default.roleArn)
    }

    func testECSMetaDataClientDefaultHost() {
        XCTAssertEqual(ECSMetaDataClient.Host, "http://169.254.170.2")
        XCTAssertEqual(ECSMetaDataClient.RelativeURIEnvironmentName, "AWS_CONTAINER_CREDENTIALS_RELATIVE_URI")
    }

    func testECSMetaDataClientIsNotCreatedWithoutEnvVariable() {
        Environment.unset(name: ECSMetaDataClient.RelativeURIEnvironmentName)
        XCTAssertNil(ECSMetaDataClient(httpClient: MockHTTPClient.ecsMetadataServer(path: "/"), host: "http://localhost"))
    }

    // MARK: - InstanceMetaDataClient -

    func testEC2InstanceMetaDataClientUsingVersion2() async throws {
        let path = "/" + UUID().uuidString
        Environment.set(path, for: ECSMetaDataClient.RelativeURIEnvironmentName)
        defer { Environment.unset(name: ECSMetaDataClient.RelativeURIEnvironmentName) }

        let client = InstanceMetaDataClient(httpClient: MockHTTPClient.ec2MetadataServer(version: .v2), host: "http://localhost:8080")
        let metaData = try await client.getMetaData(logger: TestEnvironment.logger)

        XCTAssertEqual(metaData.accessKeyId, MockHTTPClient.EC2InstanceMetaData.default.accessKeyId)
        XCTAssertEqual(metaData.secretAccessKey, MockHTTPClient.EC2InstanceMetaData.default.secretAccessKey)
        XCTAssertEqual(metaData.token, MockHTTPClient.EC2InstanceMetaData.default.token)
        XCTAssertEqual(
            metaData.expiration.timeIntervalSinceNow,
            MockHTTPClient.EC2InstanceMetaData.default.expiration.timeIntervalSinceNow,
            accuracy: 1.0
        )
        XCTAssertEqual(metaData.code, MockHTTPClient.EC2InstanceMetaData.default.code)
        XCTAssertEqual(metaData.lastUpdated, MockHTTPClient.EC2InstanceMetaData.default.lastUpdated)
        XCTAssertEqual(metaData.type, MockHTTPClient.EC2InstanceMetaData.default.type)
    }

    func testEC2InstanceMetaDataClientUsingVersion1() async throws {
        let client = InstanceMetaDataClient(httpClient: MockHTTPClient.ec2MetadataServer(version: .v1), host: "http://localhost:8080")
        let metaData = try await client.getMetaData(logger: TestEnvironment.logger)

        XCTAssertEqual(metaData.accessKeyId, MockHTTPClient.EC2InstanceMetaData.default.accessKeyId)
        XCTAssertEqual(metaData.secretAccessKey, MockHTTPClient.EC2InstanceMetaData.default.secretAccessKey)
        XCTAssertEqual(metaData.token, MockHTTPClient.EC2InstanceMetaData.default.token)
        XCTAssertEqual(
            metaData.expiration.timeIntervalSinceNow,
            MockHTTPClient.EC2InstanceMetaData.default.expiration.timeIntervalSinceNow,
            accuracy: 1.0
        )
        XCTAssertEqual(metaData.code, MockHTTPClient.EC2InstanceMetaData.default.code)
        XCTAssertEqual(metaData.lastUpdated, MockHTTPClient.EC2InstanceMetaData.default.lastUpdated)
        XCTAssertEqual(metaData.type, MockHTTPClient.EC2InstanceMetaData.default.type)
    }

    func testEC2UInstanceMetaDataClientDefaultHost() {
        XCTAssertEqual(InstanceMetaDataClient.Host, "http://169.254.169.254")
    }

    func testEC2RotatingCredentialProviderShutdown() async throws {
        let customEC2: CredentialProviderFactory = .custom { context in
            let client = InstanceMetaDataClient(httpClient: context.httpClient)
            return RotatingCredentialProvider(context: context, provider: client)
        }

        let client = createAWSClient(credentialProvider: customEC2, httpClient: MockHTTPClient.ec2MetadataServer(version: .v2))
        try await withClient(client) {
            let credential = try await client.credentialProvider.getCredential(logger: .current)
            XCTAssertEqual(credential.accessKeyId, MockHTTPClient.EC2InstanceMetaData.default.accessKeyId)
            XCTAssertEqual(credential.secretAccessKey, MockHTTPClient.EC2InstanceMetaData.default.secretAccessKey)
            XCTAssertEqual(credential.sessionToken, MockHTTPClient.EC2InstanceMetaData.default.token)
            XCTAssertEqual(
                credential.expiration.timeIntervalSinceNow,
                MockHTTPClient.EC2InstanceMetaData.default.expiration.timeIntervalSinceNow,
                accuracy: 1.0
            )
        }
    }
}
