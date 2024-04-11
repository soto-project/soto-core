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
#if compiler(<5.9) && os(Linux)
@preconcurrency import struct Foundation.Date
#else
import struct Foundation.Date
#endif
import struct Foundation.TimeInterval
import NIOPosix

struct STSAssumeRoleRequest: AWSEncodableShape {
    /// The Amazon Resource Name (ARN) of the role to assume.
    let roleArn: String
    /// An identifier for the assumed role session. Use the role session name to uniquely identify a session when the same role is assumed by different principals or for different reasons. In cross-account scenarios, the role session name is visible to, and can be logged by the account that owns the role. The role session name is also used in the ARN of the assumed role principal. This means that subsequent cross-account API requests that use the temporary security credentials will expose the role session name to the external account in their AWS CloudTrail logs. The regex used to validate this parameter is a string of characters consisting of upper- and lower-case alphanumeric characters with no spaces. You can also include underscores or any of the following characters: =,.@-
    let roleSessionName: String

    init(roleArn: String, roleSessionName: String) {
        self.roleArn = roleArn
        self.roleSessionName = roleSessionName
    }

    func validate(name: String) throws {
        try self.validate(self.roleArn, name: "roleArn", parent: name, max: 2048)
        try self.validate(self.roleArn, name: "roleArn", parent: name, min: 20)
        try self.validate(self.roleArn, name: "roleArn", parent: name, pattern: "[\\u0009\\u000A\\u000D\\u0020-\\u007E\\u0085\\u00A0-\\uD7FF\\uE000-\\uFFFD\\u10000-\\u10FFFF]+")
        try self.validate(self.roleSessionName, name: "roleSessionName", parent: name, max: 64)
        try self.validate(self.roleSessionName, name: "roleSessionName", parent: name, min: 2)
        try self.validate(self.roleSessionName, name: "roleSessionName", parent: name, pattern: "[\\w+=,.@-]*")
    }

    private enum CodingKeys: String, CodingKey {
        case roleArn = "RoleArn"
        case roleSessionName = "RoleSessionName"
    }
}

struct STSAssumeRoleResponse: AWSDecodableShape {
    /// The temporary security credentials, which include an access key ID, a secret access key, and a security (or session) token.  The size of the security token that STS API operations return is not fixed. We strongly recommend that you make no assumptions about the maximum size.
    let credentials: STSCredentials?

    private enum CodingKeys: String, CodingKey {
        case credentials = "Credentials"
    }
}

struct STSAssumeRoleWithWebIdentityRequest: AWSEncodableShape {
    /// The Amazon Resource Name (ARN) of the role that the caller is assuming.
    let roleArn: String
    /// An identifier for the assumed role session. Typically, you pass the name or identifier that is associated with the user who is using your application. That way, the temporary security credentials that your application will use are associated with that user. This session name is included as part of the ARN and assumed role ID in the AssumedRoleUser response element. The regex used to validate this parameter is a string of characters  consisting of upper- and lower-case alphanumeric characters with no spaces. You can  also include underscores or any of the following characters: =,.@-
    let roleSessionName: String
    /// The OAuth 2.0 access token or OpenID Connect ID token that is provided by the identity provider. Your application must get this token by authenticating the user who is using your application with a web identity provider before the application makes an AssumeRoleWithWebIdentity call. Only tokens with RSA algorithms (RS256) are supported.
    let webIdentityToken: String

    init(roleArn: String, roleSessionName: String, webIdentityToken: String) {
        self.roleArn = roleArn
        self.roleSessionName = roleSessionName
        self.webIdentityToken = webIdentityToken
    }

    func validate(name: String) throws {
        try self.validate(self.roleArn, name: "roleArn", parent: name, max: 2048)
        try self.validate(self.roleArn, name: "roleArn", parent: name, min: 20)
        try self.validate(self.roleArn, name: "roleArn", parent: name, pattern: "^[\\u0009\\u000A\\u000D\\u0020-\\u007E\\u0085\\u00A0-\\uD7FF\\uE000-\\uFFFD\\u10000-\\u10FFFF]+$")
        try self.validate(self.roleSessionName, name: "roleSessionName", parent: name, max: 64)
        try self.validate(self.roleSessionName, name: "roleSessionName", parent: name, min: 2)
        try self.validate(self.roleSessionName, name: "roleSessionName", parent: name, pattern: "^[\\w+=,.@-]*$")
        try self.validate(self.webIdentityToken, name: "webIdentityToken", parent: name, max: 20000)
        try self.validate(self.webIdentityToken, name: "webIdentityToken", parent: name, min: 4)
    }

    private enum CodingKeys: String, CodingKey {
        case roleArn = "RoleArn"
        case roleSessionName = "RoleSessionName"
        case webIdentityToken = "WebIdentityToken"
    }
}

struct STSAssumeRoleWithWebIdentityResponse: AWSDecodableShape {
    /// The temporary security credentials, which include an access key ID, a secret access key, and a security token.  The size of the security token that STS API operations return is not fixed. We strongly recommend that you make no assumptions about the maximum size.
    let credentials: STSCredentials?

    private enum CodingKeys: String, CodingKey {
        case credentials = "Credentials"
    }
}

struct STSCredentials: AWSDecodableShape, ExpiringCredential {
    /// The access key ID that identifies the temporary security credentials.
    let accessKeyId: String
    /// The date on which the current credentials expire.
    let expiration: Date
    /// The secret access key that can be used to sign requests.
    let secretAccessKey: String
    /// The token that users must pass to the service API to use the temporary credentials.
    let sessionToken: String?

    init(accessKeyId: String, expiration: Date, secretAccessKey: String, sessionToken: String) {
        self.accessKeyId = accessKeyId
        self.expiration = expiration
        self.secretAccessKey = secretAccessKey
        self.sessionToken = sessionToken
    }

    func isExpiring(within interval: TimeInterval) -> Bool {
        return self.expiration.timeIntervalSinceNow < interval
    }

    private enum CodingKeys: String, CodingKey {
        case accessKeyId = "AccessKeyId"
        case expiration = "Expiration"
        case secretAccessKey = "SecretAccessKey"
        case sessionToken = "SessionToken"
    }
}

/// Credential Provider that holds an AWSClient
protocol CredentialProviderWithClient: CredentialProvider {
    var client: AWSClient { get }
}

extension CredentialProviderWithClient {
    /// shutdown credential provider and client
    func shutdown() async throws {
        try await client.shutdown()
    }
}

/// Internal version of AssumeRole credential provider used by ConfigFileCredentialProvider
struct STSAssumeRoleCredentialProvider: CredentialProviderWithClient {
    enum Request {
        case assumeRole(arn: String, sessionName: String)
        case assumeRoleWithWebIdentity(arn: String, sessionName: String, tokenFile: String, threadPool: NIOThreadPool)
    }

    let request: Request
    let client: AWSClient
    let config: AWSServiceConfig

    init(
        roleArn: String,
        roleSessionName: String,
        credentialProvider: CredentialProviderFactory,
        region: Region,
        httpClient: AWSHTTPClient,
        endpoint: String? = nil
    ) {
        self.client = AWSClient(credentialProvider: credentialProvider, httpClient: httpClient)
        self.request = .assumeRole(arn: roleArn, sessionName: roleSessionName)
        self.config = AWSServiceConfig(
            region: region,
            partition: region.partition,
            serviceName: "STS",
            serviceIdentifier: "sts",
            serviceProtocol: .query,
            apiVersion: "2011-06-15",
            endpoint: endpoint,
            errorType: nil
        )
    }

    init(
        roleArn: String,
        roleSessionName: String,
        webIdentityTokenFile: String,
        region: Region,
        httpClient: AWSHTTPClient,
        endpoint: String? = nil,
        threadPool: NIOThreadPool = .singleton
    ) {
        self.client = AWSClient(credentialProvider: .empty, httpClient: httpClient)
        self.request = .assumeRoleWithWebIdentity(
            arn: roleArn,
            sessionName: roleSessionName,
            tokenFile: webIdentityTokenFile,
            threadPool: threadPool
        )
        self.config = AWSServiceConfig(
            region: region,
            partition: region.partition,
            serviceName: "STS",
            serviceIdentifier: "sts",
            serviceProtocol: .query,
            apiVersion: "2011-06-15",
            endpoint: endpoint,
            errorType: nil
        )
    }

    func getCredential(logger: Logger) async throws -> Credential {
        let credentials: STSCredentials?
        switch self.request {
        case .assumeRole(let arn, let sessioName):
            let request = STSAssumeRoleRequest(roleArn: arn, roleSessionName: sessioName)
            credentials = try await self.assumeRole(request, logger: logger).credentials
        case .assumeRoleWithWebIdentity(let arn, let sessioName, let tokenFile, let threadPool):
            // load token id file
            let fileIO = NonBlockingFileIO(threadPool: threadPool)
            let token: String
            do {
                let tokenBuffer = try await ConfigFileLoader.loadFile(path: tokenFile, fileIO: fileIO)
                token = String(buffer: tokenBuffer)
            } catch {
                throw CredentialProviderError.tokenIdFileFailedToLoad
            }
            let request = STSAssumeRoleWithWebIdentityRequest(roleArn: arn, roleSessionName: sessioName, webIdentityToken: token)
            credentials = try await self.assumeRoleWithWebIdentity(request, logger: logger).credentials
        }
        guard let credentials else {
            throw CredentialProviderError.noProvider
        }
        return credentials
    }

    func assumeRole(_ input: STSAssumeRoleRequest, logger: Logger) async throws -> STSAssumeRoleResponse {
        return try await self.client.execute(
            operation: "AssumeRole",
            path: "/",
            httpMethod: .POST,
            serviceConfig: self.config,
            input: input,
            logger: logger
        )
    }

    func assumeRoleWithWebIdentity(_ input: STSAssumeRoleWithWebIdentityRequest, logger: Logger) async throws -> STSAssumeRoleWithWebIdentityResponse {
        return try await self.client.execute(
            operation: "AssumeRoleWithWebIdentity",
            path: "/",
            httpMethod: .POST,
            serviceConfig: self.config,
            input: input,
            logger: logger
        )
    }
}

extension STSAssumeRoleCredentialProvider {
    static func fromEnvironment(
        context: CredentialProviderFactory.Context,
        endpoint: String? = nil,
        threadPool: NIOThreadPool = .singleton
    ) -> Self? {
        guard let roleArn = Environment["AWS_ROLE_ARN"],
              let roleSessionName = Environment["AWS_ROLE_SESSION_NAME"],
              let webIdentityTokenFile = Environment["AWS_WEB_IDENTITY_TOKEN_FILE"] else { return nil }
        let region = Environment["AWS_REGION"].flatMap(Region.init(awsRegionName:)) ?? .useast1
        return STSAssumeRoleCredentialProvider(
            roleArn: roleArn,
            roleSessionName: roleSessionName,
            webIdentityTokenFile: webIdentityTokenFile,
            region: region,
            httpClient: context.httpClient,
            endpoint: endpoint,
            threadPool: threadPool
        )
    }
}
