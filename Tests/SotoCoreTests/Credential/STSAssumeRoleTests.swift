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

import AsyncHTTPClient
import NIOCore
import NIOPosix
import SotoTestUtils
import SotoXML
import XCTest

@testable import SotoCore

class STSAssumeRoleTests: XCTestCase {
    func testInternalSTSAssumeRoleProvider() async throws {
        let credentials = STSCredentials(
            accessKeyId: "STSACCESSKEYID",
            expiration: Date(timeIntervalSinceNow: 1_000_000),
            secretAccessKey: "STSSECRETACCESSKEY",
            sessionToken: "STSSESSIONTOKEN"
        )
        let testServer = AWSTestServer(serviceProtocol: .xml)
        defer { XCTAssertNoThrow(try testServer.stop()) }
        let client = AWSClient(
            credentialProvider: .internalSTSAssumeRole(
                roleArn: "arn:aws:iam::000000000000:role/test-sts-assume-role",
                roleSessionName: "testInternalSTSAssumeRoleProvider",
                credentialProvider: .empty,
                region: .useast1,
                endpoint: testServer.address
            ),
            logger: TestEnvironment.logger
        )
        defer { XCTAssertNoThrow(try client.syncShutdown()) }
        async let credentialTask: Credential = client.credentialProvider.getCredential(logger: TestEnvironment.logger)
        XCTAssertNoThrow(
            try testServer.processRaw { _ in
                let output = STSAssumeRoleResponse(credentials: credentials)
                let xml = try XMLEncoder().encode(output)
                let byteBuffer = xml.map { ByteBuffer(string: $0.xmlString) } ?? .init()
                let response = AWSTestServer.Response(httpStatus: .ok, headers: [:], body: byteBuffer)
                return .result(response)
            }
        )
        let credential = try await credentialTask
        let stsCredentials = credential as? STSCredentials
        XCTAssertEqual(stsCredentials?.accessKeyId, credentials.accessKeyId)
        XCTAssertEqual(stsCredentials?.secretAccessKey, credentials.secretAccessKey)
        XCTAssertEqual(stsCredentials?.sessionToken, credentials.sessionToken)
    }

    func testSTSAssumeRoleEnvironmentVariables() async throws {
        Environment.set("arn:aws:iam::000000000000:role/test-sts-role-arn-env-role", for: "AWS_ROLE_ARN")
        Environment.set("testSTSAssumeRoleEnvironmentVariables", for: "AWS_ROLE_SESSION_NAME")
        Environment.set("temp_webidentity_token", for: "AWS_WEB_IDENTITY_TOKEN_FILE")
        defer {
            Environment.unset(name: "AWS_ROLE_ARN")
            Environment.unset(name: "AWS_ROLE_SESSION_NAME")
            Environment.unset(name: "AWS_WEB_IDENTITY_TOKEN_FILE")
        }
        let fileIO = NonBlockingFileIO(threadPool: .singleton)
        let webIdentityToken = "TestThis"
        // Write token to file referenced by AWS_WEB_IDENTITY_TOKEN_FILE env variable
        try await fileIO.withFileHandle(path: "temp_webidentity_token", mode: .write, flags: .allowFileCreation()) { fileHandle in
            try await fileIO.write(fileHandle: fileHandle, buffer: ByteBuffer(string: webIdentityToken))
        }
        try await withTeardown {
            let testServer = AWSTestServer(serviceProtocol: .xml)
            defer { XCTAssertNoThrow(try testServer.stop()) }
            let client = AWSClient(
                credentialProvider: .environment(endpoint: testServer.address),
                logger: TestEnvironment.logger
            )
            defer { XCTAssertNoThrow(try client.syncShutdown()) }
            async let credentialTask: Credential = client.credentialProvider.getCredential(logger: TestEnvironment.logger)
            XCTAssertNoThrow(
                try testServer.processRaw { request in
                    let tokens = String(buffer: request.body).split(separator: "&")
                    let webIdentityToken = try XCTUnwrap(tokens.first { $0.hasPrefix("WebIdentityToken=") })
                    let credentials = STSCredentials(
                        accessKeyId: "STSACCESSKEYID",
                        expiration: Date(timeIntervalSinceNow: 1_000_000),
                        secretAccessKey: "STSSECRETACCESSKEY",
                        sessionToken: String(webIdentityToken)
                    )
                    let output = STSAssumeRoleResponse(credentials: credentials)
                    let xml = try XMLEncoder().encode(output)
                    let byteBuffer = xml.map { ByteBuffer(string: $0.xmlString) } ?? .init()
                    let response = AWSTestServer.Response(httpStatus: .ok, headers: [:], body: byteBuffer)
                    return .result(response)
                }
            )
            let credential = try await credentialTask
            let stsCredentials = try XCTUnwrap(credential as? STSCredentials)
            XCTAssertEqual(stsCredentials.sessionToken, "WebIdentityToken=TestThis")
        } teardown: {
            try? await fileIO.remove(path: "temp_webidentity_token")
        }
    }

    func testSTSAssumeRoleEnvironmentVariablesNoFile() async throws {
        Environment.set("arn:aws:iam::000000000000:role/test-sts-role-arn-env-role", for: "AWS_ROLE_ARN")
        Environment.set("testSTSAssumeRoleEnvironmentVariables", for: "AWS_ROLE_SESSION_NAME")
        Environment.set("/doesntexist", for: "AWS_WEB_IDENTITY_TOKEN_FILE")
        defer {
            Environment.unset(name: "AWS_ROLE_ARN")
            Environment.unset(name: "AWS_ROLE_SESSION_NAME")
            Environment.unset(name: "AWS_WEB_IDENTITY_TOKEN_FILE")
        }
        let client = AWSClient(
            credentialProvider: .environment(),
            logger: TestEnvironment.logger
        )
        defer { XCTAssertNoThrow(try client.syncShutdown()) }
        do {
            _ = try await client.credentialProvider.getCredential(logger: TestEnvironment.logger)
            XCTFail("Get credential should fail as token id file does not exist")
        } catch let error as CredentialProviderError where error == .tokenIdFileFailedToLoad {}
    }
}

// Extend STSAssumeRoleRequest so it can be used with the AWSTestServer
extension STSAssumeRoleRequest: Decodable {
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let roleArn = try container.decode(String.self, forKey: .roleArn)
        let roleSessionName = try container.decode(String.self, forKey: .roleSessionName)
        self.init(roleArn: roleArn, roleSessionName: roleSessionName)
    }

    private enum CodingKeys: String, CodingKey {
        case roleArn = "RoleArn"
        case roleSessionName = "RoleSessionName"
    }
}

// Extend STSAssumeRoleResponse so it can be used with the AWSTestServer
extension STSAssumeRoleResponse: Encodable {
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(credentials, forKey: .credentials)
    }

    private enum CodingKeys: String, CodingKey {
        case credentials = "Credentials"
    }
}

// Extend STSAssumeRoleWithWebIdentityResponse so it can be used with the AWSTestServer
extension STSAssumeRoleWithWebIdentityResponse: Encodable {
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(credentials, forKey: .credentials)
    }

    private enum CodingKeys: String, CodingKey {
        case credentials = "Credentials"
    }
}

// Extend STSCredentials so it can be used with the AWSTestServer
extension STSCredentials: Encodable {
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(accessKeyId, forKey: .accessKeyId)
        try container.encode(expiration, forKey: .expiration)
        try container.encode(secretAccessKey, forKey: .secretAccessKey)
        try container.encode(sessionToken, forKey: .sessionToken)
    }

    private enum CodingKeys: String, CodingKey {
        case accessKeyId = "AccessKeyId"
        case expiration = "Expiration"
        case secretAccessKey = "SecretAccessKey"
        case sessionToken = "SessionToken"
    }
}

extension CredentialProviderFactory {
    /// Internal version of AssumeRole credential provider used by ConfigFileCredentialProvider
    /// - Parameters:
    ///   - request: AssumeRole request structure
    ///   - credentialProvider: Credential provider used in client that runs the AssumeRole operation
    ///   - region: Region to run request in
    static func internalSTSAssumeRole(
        roleArn: String,
        roleSessionName: String,
        credentialProvider: CredentialProviderFactory = .default,
        region: Region,
        endpoint: String? = nil
    ) -> CredentialProviderFactory {
        .custom { context in
            let provider = STSAssumeRoleCredentialProvider(
                roleArn: roleArn,
                roleSessionName: roleSessionName,
                credentialProvider: credentialProvider,
                region: region,
                httpClient: context.httpClient,
                endpoint: endpoint
            )
            return RotatingCredentialProvider(context: context, provider: provider)
        }
    }
}
