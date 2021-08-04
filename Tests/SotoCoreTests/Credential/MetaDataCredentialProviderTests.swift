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
import XCTest

class MetaDataCredentialProviderTests: XCTestCase {
    // MARK: - ECSMetaDataClient -

    func testECSMetaDataClient() {
        let group = MultiThreadedEventLoopGroup(numberOfThreads: 1)
        defer { XCTAssertNoThrow(try group.syncShutdownGracefully()) }

        let loop = group.next()
        let httpClient = HTTPClient(eventLoopGroupProvider: .shared(loop))
        defer { XCTAssertNoThrow(try httpClient.syncShutdown()) }
        let testServer = AWSTestServer(serviceProtocol: .json)
        defer { XCTAssertNoThrow(try testServer.stop()) }

        let path = "/" + UUID().uuidString
        Environment.set(path, for: ECSMetaDataClient.RelativeURIEnvironmentName)
        defer { Environment.unset(name: ECSMetaDataClient.RelativeURIEnvironmentName) }

        let client = ECSMetaDataClient(httpClient: httpClient, host: testServer.address)
        let future = client!.getMetaData(on: loop, context: TestEnvironment.loggingContext)

        XCTAssertNoThrow(try testServer.ecsMetadataServer(path: path))

        var metaData: ECSMetaDataClient.MetaData?
        XCTAssertNoThrow(metaData = try future.wait())

        XCTAssertEqual(metaData?.accessKeyId, AWSTestServer.ECSMetaData.default.accessKeyId)
        XCTAssertEqual(metaData?.secretAccessKey, AWSTestServer.ECSMetaData.default.secretAccessKey)
        XCTAssertEqual(metaData?.token, AWSTestServer.ECSMetaData.default.token)
        XCTAssertEqual(metaData?.expiration.description, AWSTestServer.ECSMetaData.default.expiration.description)
        XCTAssertEqual(metaData?.roleArn, AWSTestServer.ECSMetaData.default.roleArn)
    }

    func testECSMetaDataClientDefaultHost() {
        XCTAssertEqual(ECSMetaDataClient.Host, "http://169.254.170.2")
        XCTAssertEqual(ECSMetaDataClient.RelativeURIEnvironmentName, "AWS_CONTAINER_CREDENTIALS_RELATIVE_URI")
    }

    func testECSMetaDataClientIsNotCreatedWithoutEnvVariable() {
        let group = MultiThreadedEventLoopGroup(numberOfThreads: 1)
        defer { XCTAssertNoThrow(try group.syncShutdownGracefully()) }

        let loop = group.next()
        let httpClient = HTTPClient(eventLoopGroupProvider: .shared(loop))
        defer { XCTAssertNoThrow(try httpClient.syncShutdown()) }

        Environment.unset(name: ECSMetaDataClient.RelativeURIEnvironmentName)

        XCTAssertNil(ECSMetaDataClient(httpClient: httpClient, host: "http://localhost"))
    }

    // MARK: - InstanceMetaDataClient -

    func testEC2InstanceMetaDataClientUsingVersion2() {
        let group = MultiThreadedEventLoopGroup(numberOfThreads: 1)
        defer { XCTAssertNoThrow(try group.syncShutdownGracefully()) }

        let loop = group.next()
        let httpClient = HTTPClient(eventLoopGroupProvider: .shared(loop))
        defer { XCTAssertNoThrow(try httpClient.syncShutdown()) }
        let testServer = AWSTestServer(serviceProtocol: .json)
        defer { XCTAssertNoThrow(try testServer.stop()) }

        let path = "/" + UUID().uuidString
        Environment.set(path, for: ECSMetaDataClient.RelativeURIEnvironmentName)
        defer { Environment.unset(name: ECSMetaDataClient.RelativeURIEnvironmentName) }

        let client = InstanceMetaDataClient(httpClient: httpClient, host: testServer.address)
        let future = client.getMetaData(on: loop, context: TestEnvironment.loggingContext)

        XCTAssertNoThrow(try testServer.ec2MetadataServer(version: .v2))

        var metaData: InstanceMetaDataClient.MetaData?
        XCTAssertNoThrow(metaData = try future.wait())

        XCTAssertEqual(metaData?.accessKeyId, AWSTestServer.EC2InstanceMetaData.default.accessKeyId)
        XCTAssertEqual(metaData?.secretAccessKey, AWSTestServer.EC2InstanceMetaData.default.secretAccessKey)
        XCTAssertEqual(metaData?.token, AWSTestServer.EC2InstanceMetaData.default.token)
        XCTAssertEqual(metaData?.expiration.description, AWSTestServer.EC2InstanceMetaData.default.expiration.description)
        XCTAssertEqual(metaData?.code, AWSTestServer.EC2InstanceMetaData.default.code)
        XCTAssertEqual(metaData?.lastUpdated, AWSTestServer.EC2InstanceMetaData.default.lastUpdated)
        XCTAssertEqual(metaData?.type, AWSTestServer.EC2InstanceMetaData.default.type)
    }

    func testEC2InstanceMetaDataClientUsingVersion1() {
        let group = MultiThreadedEventLoopGroup(numberOfThreads: 1)
        defer { XCTAssertNoThrow(try group.syncShutdownGracefully()) }

        let loop = group.next()
        let httpClient = HTTPClient(eventLoopGroupProvider: .shared(loop))
        defer { XCTAssertNoThrow(try httpClient.syncShutdown()) }
        let testServer = AWSTestServer(serviceProtocol: .json)
        defer { XCTAssertNoThrow(try testServer.stop()) }

        let client = InstanceMetaDataClient(httpClient: httpClient, host: testServer.address)
        let future = client.getMetaData(on: loop, context: TestEnvironment.loggingContext)

        XCTAssertNoThrow(try testServer.ec2MetadataServer(version: .v1))

        var metaData: InstanceMetaDataClient.MetaData?
        XCTAssertNoThrow(metaData = try future.wait())

        XCTAssertEqual(metaData?.accessKeyId, AWSTestServer.EC2InstanceMetaData.default.accessKeyId)
        XCTAssertEqual(metaData?.secretAccessKey, AWSTestServer.EC2InstanceMetaData.default.secretAccessKey)
        XCTAssertEqual(metaData?.token, AWSTestServer.EC2InstanceMetaData.default.token)
        XCTAssertEqual(metaData?.expiration.description, AWSTestServer.EC2InstanceMetaData.default.expiration.description)
        XCTAssertEqual(metaData?.code, AWSTestServer.EC2InstanceMetaData.default.code)
        XCTAssertEqual(metaData?.lastUpdated, AWSTestServer.EC2InstanceMetaData.default.lastUpdated)
        XCTAssertEqual(metaData?.type, AWSTestServer.EC2InstanceMetaData.default.type)
    }

    func testEC2UInstanceMetaDataClientDefaultHost() {
        XCTAssertEqual(InstanceMetaDataClient.Host, "http://169.254.169.254")
    }

    func testEC2RotatingCredentialProviderShutdown() {
        let testServer = AWSTestServer(serviceProtocol: .json)
        defer { XCTAssertNoThrow(try testServer.stop()) }
        let customEC2: CredentialProviderFactory = .custom { context in
            let client = InstanceMetaDataClient(httpClient: context.httpClient, host: testServer.address)
            return RotatingCredentialProvider(context: context, provider: client)
        }

        let client = createAWSClient(credentialProvider: customEC2)
        XCTAssertNoThrow(try testServer.ec2MetadataServer(version: .v2))
        XCTAssertNoThrow(try client.syncShutdown())
    }
}
