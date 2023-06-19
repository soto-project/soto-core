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

import NIOCore
@testable import SotoCore
import SotoTestUtils
import XCTest

class RuntimeSelectorCredentialProviderTests: XCTestCase {
    func testSetupFail() async {
        let client = createAWSClient(credentialProvider: .selector(.custom { _ in return NullCredentialProvider() }))
        defer { XCTAssertNoThrow(try client.syncShutdown()) }
        do {
            _ = try await client.credentialProvider.getCredential(logger: TestEnvironment.logger)
            XCTFail("Shouldn't get here")
        } catch {
            XCTAssertEqual(error as? CredentialProviderError, CredentialProviderError.noProvider)
        }
    }

    func testShutdown() async throws {
        let client = createAWSClient(credentialProvider: .selector(.environment, .configFile()))
        try await client.shutdown()
    }

    func testFoundEnvironmentProvider() async throws {
        let accessKeyId = "AWSACCESSKEYID"
        let secretAccessKey = "AWSSECRETACCESSKEY"
        let sessionToken = "AWSSESSIONTOKEN"

        Environment.set(accessKeyId, for: "AWS_ACCESS_KEY_ID")
        Environment.set(secretAccessKey, for: "AWS_SECRET_ACCESS_KEY")
        Environment.set(sessionToken, for: "AWS_SESSION_TOKEN")

        let client = createAWSClient(credentialProvider: .selector(.environment, .empty))
        defer { XCTAssertNoThrow(try client.syncShutdown()) }
        let credential = try await client.credentialProvider.getCredential(logger: TestEnvironment.logger)
        XCTAssertEqual(credential.accessKeyId, accessKeyId)
        XCTAssertEqual(credential.secretAccessKey, secretAccessKey)
        XCTAssertEqual(credential.sessionToken, sessionToken)
        let internalProvider = try await(client.credentialProvider as? RuntimeSelectorCredentialProvider)?.getTaskProviderTask()
        XCTAssert(internalProvider is StaticCredential)

        Environment.unset(name: "AWS_ACCESS_KEY_ID")
        Environment.unset(name: "AWS_SECRET_ACCESS_KEY")
        Environment.unset(name: "AWS_SESSION_TOKEN")
    }

    func testEnvironmentProviderFail() async throws {
        Environment.unset(name: "AWS_ACCESS_KEY_ID")

        let provider: CredentialProviderFactory = .selector(.environment)
        let client = createAWSClient(credentialProvider: provider)
        defer { XCTAssertNoThrow(try client.syncShutdown()) }
        do {
            _ = try await client.credentialProvider.getCredential(logger: TestEnvironment.logger)
            XCTFail("Should not get here")
        } catch {
            XCTAssertEqual(error as? CredentialProviderError, CredentialProviderError.noProvider)
        }
    }

    func testFoundEmptyProvider() async throws {
        let provider: CredentialProviderFactory = .selector(.empty, .environment)
        let client = createAWSClient(credentialProvider: provider)
        defer { XCTAssertNoThrow(try client.syncShutdown()) }
        let credential = try await client.credentialProvider.getCredential(logger: TestEnvironment.logger)
        XCTAssertEqual(credential.accessKeyId, "")
        XCTAssertEqual(credential.secretAccessKey, "")
        XCTAssertEqual(credential.sessionToken, nil)
        let internalProvider = try await(client.credentialProvider as? RuntimeSelectorCredentialProvider)?.getTaskProviderTask()
        XCTAssert(internalProvider is StaticCredential)
    }

    func testFoundSelectorWithOneProvider() async throws {
        let provider: CredentialProviderFactory = .selector(.empty)
        let client = createAWSClient(credentialProvider: provider)
        defer { XCTAssertNoThrow(try client.syncShutdown()) }
        let credential = try await client.credentialProvider.getCredential(logger: TestEnvironment.logger)
        XCTAssert(credential.isEmpty())
        XCTAssert(client.credentialProvider is StaticCredential)
    }

    func testECSProvider() async throws {
        Environment.unset(name: "AWS_ACCESS_KEY_ID")

        let testServer = AWSTestServer(serviceProtocol: .json)
        defer { XCTAssertNoThrow(try testServer.stop()) }
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
        defer { XCTAssertNoThrow(try client.syncShutdown()) }

        async let credentialTask = client.credentialProvider.getCredential(logger: TestEnvironment.logger)

        XCTAssertNoThrow(try testServer.ecsMetadataServer(path: path))

        let credential = try await credentialTask
        XCTAssertEqual(credential.accessKeyId, AWSTestServer.ECSMetaData.default.accessKeyId)
        XCTAssertEqual(credential.secretAccessKey, AWSTestServer.ECSMetaData.default.secretAccessKey)
        XCTAssertEqual(credential.sessionToken, AWSTestServer.ECSMetaData.default.token)
        let internalProvider = try await(client.credentialProvider as? RuntimeSelectorCredentialProvider)?.getTaskProviderTask()
        XCTAssert(internalProvider is RotatingCredentialProvider)
    }

    func testECSProviderFail() async {
        Environment.unset(name: "AWS_ACCESS_KEY_ID")
        Environment.unset(name: ECSMetaDataClient.RelativeURIEnvironmentName)

        let provider: CredentialProviderFactory = .selector(.ecs)
        let client = createAWSClient(credentialProvider: provider)
        defer { XCTAssertNoThrow(try client.syncShutdown()) }
        do {
            _ = try await client.credentialProvider.getCredential(logger: TestEnvironment.logger)
            XCTFail("Should not get here")
        } catch {
            XCTAssertEqual(error as? CredentialProviderError, .noProvider)
        }
    }

    func testEC2Provider() async throws {
        let testServer = AWSTestServer(serviceProtocol: .json)
        defer { XCTAssertNoThrow(try testServer.stop()) }
        let customEC2: CredentialProviderFactory = .custom { context in
            let client = InstanceMetaDataClient(httpClient: context.httpClient, host: testServer.address)
            return RotatingCredentialProvider(context: context, provider: client)
        }

        let client = createAWSClient(credentialProvider: .selector(customEC2, .empty))
        defer { XCTAssertNoThrow(try client.syncShutdown()) }
        async let credentialTask = client.credentialProvider.getCredential(logger: TestEnvironment.logger)

        XCTAssertNoThrow(try testServer.ec2MetadataServer(version: .v2))

        let credential = try await credentialTask
        XCTAssertEqual(credential.accessKeyId, AWSTestServer.EC2InstanceMetaData.default.accessKeyId)
        XCTAssertEqual(credential.secretAccessKey, AWSTestServer.EC2InstanceMetaData.default.secretAccessKey)
        XCTAssertEqual(credential.sessionToken, AWSTestServer.EC2InstanceMetaData.default.token)
        let internalProvider = try await(client.credentialProvider as? RuntimeSelectorCredentialProvider)?.getTaskProviderTask()
        XCTAssert(internalProvider is RotatingCredentialProvider)
    }

    func testConfigFileProvider() async throws {
        let credentials = """
        [default]
        aws_access_key_id = AWSACCESSKEYID
        aws_secret_access_key = AWSSECRETACCESSKEY
        """
        let filename = "credentials"
        let filenameURL = URL(fileURLWithPath: filename)
        XCTAssertNoThrow(try Data(credentials.utf8).write(to: filenameURL))
        defer { XCTAssertNoThrow(try FileManager.default.removeItem(at: filenameURL)) }

        let client = createAWSClient(credentialProvider: .selector(.configFile(credentialsFilePath: filename), .empty))
        defer { XCTAssertNoThrow(try client.syncShutdown()) }
        let credential = try await client.credentialProvider.getCredential(logger: TestEnvironment.logger)
        XCTAssertEqual(credential.accessKeyId, "AWSACCESSKEYID")
        XCTAssertEqual(credential.secretAccessKey, "AWSSECRETACCESSKEY")
        XCTAssertEqual(credential.sessionToken, nil)
        let internalProvider = try await(client.credentialProvider as? RuntimeSelectorCredentialProvider)?.getTaskProviderTask()
        XCTAssert(internalProvider is RotatingCredentialProvider)
    }

    func testConfigFileProviderFail() async throws {
        let client = createAWSClient(credentialProvider: .selector(.configFile(credentialsFilePath: "nonExistentCredentialFile"), .empty))
        defer { XCTAssertNoThrow(try client.syncShutdown()) }
        _ = try await client.credentialProvider.getCredential(logger: TestEnvironment.logger)
        let internalProvider = try await(client.credentialProvider as? RuntimeSelectorCredentialProvider)?.getTaskProviderTask()
        XCTAssert(internalProvider is StaticCredential)
        XCTAssert((internalProvider as? StaticCredential)?.isEmpty() == true)
    }
}
