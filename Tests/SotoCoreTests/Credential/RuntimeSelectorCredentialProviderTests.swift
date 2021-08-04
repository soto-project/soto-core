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

import NIO
@testable import SotoCore
import SotoTestUtils
import XCTest

class RuntimeSelectorCredentialProviderTests: XCTestCase {
    func testSetupFail() {
        let client = createAWSClient(credentialProvider: .selector(.custom { _ in return NullCredentialProvider() }))
        defer { XCTAssertNoThrow(try client.syncShutdown()) }
        let futureResult = client.credentialProvider.getCredential(on: client.eventLoopGroup.next(), context: TestEnvironment.loggingContext)
        XCTAssertThrowsError(try futureResult.wait()) { error in
            switch error {
            case let error as CredentialProviderError where error == CredentialProviderError.noProvider:
                break
            default:
                XCTFail()
            }
        }
    }

    func testShutdown() {
        let client = createAWSClient(credentialProvider: .selector(.environment, .configFile()))
        XCTAssertNoThrow(try client.syncShutdown())
    }

    func testFoundEnvironmentProvider() throws {
        let accessKeyId = "AWSACCESSKEYID"
        let secretAccessKey = "AWSSECRETACCESSKEY"
        let sessionToken = "AWSSESSIONTOKEN"

        Environment.set(accessKeyId, for: "AWS_ACCESS_KEY_ID")
        Environment.set(secretAccessKey, for: "AWS_SECRET_ACCESS_KEY")
        Environment.set(sessionToken, for: "AWS_SESSION_TOKEN")

        let client = createAWSClient(credentialProvider: .selector(.environment, .empty))
        defer { XCTAssertNoThrow(try client.syncShutdown()) }
        let futureResult = client.credentialProvider.getCredential(on: client.eventLoopGroup.next(), context: TestEnvironment.loggingContext).flatMapThrowing { credential in
            XCTAssertEqual(credential.accessKeyId, accessKeyId)
            XCTAssertEqual(credential.secretAccessKey, secretAccessKey)
            XCTAssertEqual(credential.sessionToken, sessionToken)
            let internalProvider = try XCTUnwrap((client.credentialProvider as? RuntimeSelectorCredentialProvider)?.internalProvider)
            XCTAssert(internalProvider is StaticCredential)
        }
        XCTAssertNoThrow(try futureResult.wait())

        Environment.unset(name: "AWS_ACCESS_KEY_ID")
        Environment.unset(name: "AWS_SECRET_ACCESS_KEY")
        Environment.unset(name: "AWS_SESSION_TOKEN")
    }

    func testEnvironmentProviderFail() throws {
        Environment.unset(name: "AWS_ACCESS_KEY_ID")

        let provider: CredentialProviderFactory = .selector(.environment)
        let client = createAWSClient(credentialProvider: provider)
        defer { XCTAssertNoThrow(try client.syncShutdown()) }
        let futureResult = client.credentialProvider.getCredential(on: client.eventLoopGroup.next(), context: TestEnvironment.loggingContext)
        XCTAssertThrowsError(try futureResult.wait()) { error in
            switch error {
            case let error as CredentialProviderError where error == CredentialProviderError.noProvider:
                break
            default:
                XCTFail()
            }
        }
    }

    func testFoundEmptyProvider() throws {
        let provider: CredentialProviderFactory = .selector(.empty, .environment)
        let client = createAWSClient(credentialProvider: provider)
        defer { XCTAssertNoThrow(try client.syncShutdown()) }
        let futureResult = client.credentialProvider.getCredential(on: client.eventLoopGroup.next(), context: TestEnvironment.loggingContext).flatMapThrowing { credential in
            XCTAssertEqual(credential.accessKeyId, "")
            XCTAssertEqual(credential.secretAccessKey, "")
            XCTAssertEqual(credential.sessionToken, nil)
            let internalProvider = try XCTUnwrap((client.credentialProvider as? RuntimeSelectorCredentialProvider)?.internalProvider)
            XCTAssert(internalProvider is StaticCredential)
        }
        XCTAssertNoThrow(try futureResult.wait())
    }

    func testFoundSelectorWithOneProvider() throws {
        let provider: CredentialProviderFactory = .selector(.empty)
        let client = createAWSClient(credentialProvider: provider)
        defer { XCTAssertNoThrow(try client.syncShutdown()) }
        let futureResult = client.credentialProvider.getCredential(on: client.eventLoopGroup.next(), context: TestEnvironment.loggingContext).flatMapThrowing { credential in
            XCTAssert(credential.isEmpty())
            XCTAssert(client.credentialProvider is StaticCredential)
        }
        XCTAssertNoThrow(try futureResult.wait())
    }

    func testECSProvider() {
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
        let futureResult = client.credentialProvider.getCredential(on: client.eventLoopGroup.next(), context: TestEnvironment.loggingContext).flatMapThrowing { credential in
            XCTAssertEqual(credential.accessKeyId, AWSTestServer.ECSMetaData.default.accessKeyId)
            XCTAssertEqual(credential.secretAccessKey, AWSTestServer.ECSMetaData.default.secretAccessKey)
            XCTAssertEqual(credential.sessionToken, AWSTestServer.ECSMetaData.default.token)
            let internalProvider = try XCTUnwrap((client.credentialProvider as? RuntimeSelectorCredentialProvider)?.internalProvider)
            XCTAssert(internalProvider is RotatingCredentialProvider)
        }

        XCTAssertNoThrow(try testServer.ecsMetadataServer(path: path))

        XCTAssertNoThrow(try futureResult.wait())
    }

    func testECSProviderFail() {
        Environment.unset(name: "AWS_ACCESS_KEY_ID")
        Environment.unset(name: ECSMetaDataClient.RelativeURIEnvironmentName)

        let provider: CredentialProviderFactory = .selector(.ecs)
        let client = createAWSClient(credentialProvider: provider)
        defer { XCTAssertNoThrow(try client.syncShutdown()) }
        let futureResult = client.credentialProvider.getCredential(on: client.eventLoopGroup.next(), context: TestEnvironment.loggingContext)
        XCTAssertThrowsError(try futureResult.wait()) { error in
            switch error {
            case let error as CredentialProviderError where error == CredentialProviderError.noProvider:
                break
            default:
                XCTFail()
            }
        }
    }

    func testEC2Provider() {
        let testServer = AWSTestServer(serviceProtocol: .json)
        defer { XCTAssertNoThrow(try testServer.stop()) }
        let customEC2: CredentialProviderFactory = .custom { context in
            let client = InstanceMetaDataClient(httpClient: context.httpClient, host: testServer.address)
            return RotatingCredentialProvider(context: context, provider: client)
        }

        let client = createAWSClient(credentialProvider: .selector(customEC2, .empty))
        defer { XCTAssertNoThrow(try client.syncShutdown()) }
        let futureResult = client.credentialProvider.getCredential(
            on: client.eventLoopGroup.next(),
            context: TestEnvironment.loggingContext
        ).flatMapThrowing { credential in
            XCTAssertEqual(credential.accessKeyId, AWSTestServer.EC2InstanceMetaData.default.accessKeyId)
            XCTAssertEqual(credential.secretAccessKey, AWSTestServer.EC2InstanceMetaData.default.secretAccessKey)
            XCTAssertEqual(credential.sessionToken, AWSTestServer.EC2InstanceMetaData.default.token)
            let internalProvider = try XCTUnwrap((client.credentialProvider as? RuntimeSelectorCredentialProvider)?.internalProvider)
            XCTAssert(internalProvider is RotatingCredentialProvider)
        }

        XCTAssertNoThrow(try testServer.ec2MetadataServer(version: .v2))

        XCTAssertNoThrow(try futureResult.wait())
    }

    func testConfigFileProvider() {
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
        let futureResult = client.credentialProvider.getCredential(on: client.eventLoopGroup.next(), context: TestEnvironment.loggingContext).flatMapThrowing { credential in
            XCTAssertEqual(credential.accessKeyId, "AWSACCESSKEYID")
            XCTAssertEqual(credential.secretAccessKey, "AWSSECRETACCESSKEY")
            XCTAssertEqual(credential.sessionToken, nil)
            let internalProvider = try XCTUnwrap((client.credentialProvider as? RuntimeSelectorCredentialProvider)?.internalProvider)
            XCTAssert(internalProvider is RotatingCredentialProvider)
        }
        XCTAssertNoThrow(try futureResult.wait())
    }

    func testConfigFileProviderFail() {
        let client = createAWSClient(credentialProvider: .selector(.configFile(credentialsFilePath: "nonExistentCredentialFile"), .empty))
        defer { XCTAssertNoThrow(try client.syncShutdown()) }
        let futureResult = client.credentialProvider.getCredential(on: client.eventLoopGroup.next(), context: TestEnvironment.loggingContext).flatMapThrowing { _ in
            let internalProvider = try XCTUnwrap((client.credentialProvider as? RuntimeSelectorCredentialProvider)?.internalProvider)
            XCTAssert(internalProvider is StaticCredential)
            XCTAssert((internalProvider as? StaticCredential)?.isEmpty() == true)
        }
        XCTAssertNoThrow(try futureResult.wait())
    }
}
