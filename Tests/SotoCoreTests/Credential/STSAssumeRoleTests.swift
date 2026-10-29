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
import HTTPTypes
import NIOCore
import NIOHTTP1
import NIOPosix
import SotoTestUtils
import SotoXML
import Testing
import _NIOFileSystem

@testable import SotoCore

@Suite(.serialized)
struct STSAssumeRoleTests {
    @Test func testInternalSTSAssumeRoleProvider() async throws {
        let credentials = STSCredentials(
            accessKeyId: "STSACCESSKEYID",
            expiration: Date(timeIntervalSinceNow: 1_000_000),
            secretAccessKey: "STSSECRETACCESSKEY",
            sessionToken: "STSSESSIONTOKEN"
        )
        let mockHTTPClient = MockHTTPClient { _ in
            let output = STSAssumeRoleResponse(credentials: credentials)
            let xml = try XMLEncoder().encode(output)
            return AWSHTTPResponse(response: .init(status: .ok), body: .init(string: xml?.xmlString ?? ""))
        }
        let client = AWSClient(
            credentialProvider: .internalSTSAssumeRole(
                roleArn: "arn:aws:iam::000000000000:role/test-sts-assume-role",
                roleSessionName: "testInternalSTSAssumeRoleProvider",
                credentialProvider: .empty,
                region: .useast1
            ),
            httpClient: mockHTTPClient,
            logger: TestEnvironment.logger
        )
        try await withClient(client) {
            let credential = try await client.credentialProvider.getCredential(logger: TestEnvironment.logger)
            #expect(credential.accessKeyId == credentials.accessKeyId)
            #expect(credential.secretAccessKey == credentials.secretAccessKey)
            #expect(credential.sessionToken == credentials.sessionToken)
        }
    }

    @Test func testSTSAssumeRoleEnvironmentVariables() async throws {
        Environment.set("arn:aws:iam::000000000000:role/test-sts-role-arn-env-role", for: "AWS_ROLE_ARN")
        Environment.set("testSTSAssumeRoleEnvironmentVariables", for: "AWS_ROLE_SESSION_NAME")
        Environment.set("temp_webidentity_token", for: "AWS_WEB_IDENTITY_TOKEN_FILE")
        defer {
            Environment.unset(name: "AWS_ROLE_ARN")
            Environment.unset(name: "AWS_ROLE_SESSION_NAME")
            Environment.unset(name: "AWS_WEB_IDENTITY_TOKEN_FILE")
        }
        let fileSystem = FileSystem(threadPool: .singleton)
        let webIdentityToken = "TestThis"
        // Write token to file referenced by AWS_WEB_IDENTITY_TOKEN_FILE env variable
        _ = try await fileSystem.withFileHandle(forWritingAt: .init("temp_webidentity_token"), options: .newFile(replaceExisting: true)) { write in
            try await write.write(contentsOf: ByteBuffer(string: webIdentityToken), toAbsoluteOffset: 0)
        }
        let mockHTTPClient = MockHTTPClient { request in
            let body = try await request.body.collect(upTo: .max)
            let tokens = String(buffer: body).split(separator: "&")
            let webIdentityToken = try #require(tokens.first { $0.hasPrefix("WebIdentityToken=") })
            let credentials = STSCredentials(
                accessKeyId: "STSACCESSKEYID",
                expiration: Date(timeIntervalSinceNow: 1_000_000),
                secretAccessKey: "STSSECRETACCESSKEY",
                sessionToken: String(webIdentityToken)
            )
            let output = STSAssumeRoleResponse(credentials: credentials)
            let xml = try XMLEncoder().encode(output)
            return AWSHTTPResponse(response: .init(status: .ok), body: .init(string: xml?.xmlString ?? ""))
        }
        let client = AWSClient(
            credentialProvider: .environment(endpoint: "http://localhost:8080"),
            httpClient: mockHTTPClient,
            logger: TestEnvironment.logger
        )
        try await withTeardown {
            let credential = try await client.credentialProvider.getCredential(logger: TestEnvironment.logger)
            #expect(credential.sessionToken == "WebIdentityToken=TestThis")
        } teardown: {
            _ = try? await fileSystem.removeItem(at: .init("temp_webidentity_token"))
            try? await client.shutdown()
        }
    }

    @Test func testSTSAssumeRoleEnvironmentVariablesNoFile() async throws {
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
            httpClient: MockHTTPClient(),
            logger: TestEnvironment.logger
        )
        try await withClient(client) {
            let error = await #expect(throws: CredentialProviderError.self) {
                _ = try await client.credentialProvider.getCredential(logger: TestEnvironment.logger)
            }
            #expect(error == .tokenIdFileFailedToLoad)
        }
    }
}

// Extend STSAssumeRoleRequest so it can be used with the MockHTTPClient
extension STSAssumeRoleRequest: Decodable {
    public init(from decoder: any Decoder) throws {
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

// Extend STSAssumeRoleResponse so it can be used with the MockHTTPClient
extension STSAssumeRoleResponse: Encodable {
    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(credentials, forKey: .credentials)
    }

    private enum CodingKeys: String, CodingKey {
        case credentials = "Credentials"
    }
}

// Extend STSAssumeRoleWithWebIdentityResponse so it can be used with the MockHTTPClient
extension STSAssumeRoleWithWebIdentityResponse: Encodable {
    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(credentials, forKey: .credentials)
    }

    private enum CodingKeys: String, CodingKey {
        case credentials = "Credentials"
    }
}

// Extend STSCredentials so it can be used with the MockHTTPClient
extension STSCredentials: Encodable {
    public func encode(to encoder: any Encoder) throws {
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
                retryPolicy: .default,
                httpClient: context.httpClient,
                endpoint: endpoint
            )
            return RotatingCredentialProvider(context: context, provider: provider)
        }
    }
}
