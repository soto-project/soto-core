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
import Baggage
import Foundation

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
    func shutdown(on eventLoop: EventLoop) -> EventLoopFuture<Void> {
        // shutdown AWSClient
        let promise = eventLoop.makePromise(of: Void.self)
        client.shutdown { error in
            if let error = error {
                promise.completeWith(.failure(error))
            } else {
                promise.completeWith(.success(()))
            }
        }
        return promise.futureResult
    }
}

/// Internal version of AssumeRole credential provider used by ConfigFileCredentialProvider
struct STSAssumeRoleCredentialProvider: CredentialProviderWithClient {
    let request: STSAssumeRoleRequest
    let client: AWSClient
    let config: AWSServiceConfig

    init(
        request: STSAssumeRoleRequest,
        credentialProvider: CredentialProviderFactory,
        region: Region,
        httpClient: AWSHTTPClient,
        endpoint: String? = nil
    ) {
        self.client = AWSClient(credentialProvider: credentialProvider, httpClientProvider: .shared(httpClient))
        self.request = request
        self.config = AWSServiceConfig(
            region: region,
            partition: region.partition,
            service: "sts",
            serviceProtocol: .query,
            apiVersion: "2011-06-15",
            endpoint: endpoint,
            errorType: nil
        )
    }

    func getCredential(on eventLoop: EventLoop, context: LoggingContext) -> EventLoopFuture<Credential> {
        self.assumeRole(self.request, context: context, on: eventLoop)
            .flatMapThrowing { response in
                guard let credentials = response.credentials else {
                    throw CredentialProviderError.noProvider
                }
                return credentials
            }
    }

    func assumeRole(_ input: STSAssumeRoleRequest, context: LoggingContext, on eventLoop: EventLoop?) -> EventLoopFuture<STSAssumeRoleResponse> {
        return self.client.execute(operation: "AssumeRole", path: "/", httpMethod: .POST, serviceConfig: self.config, input: input, context: context, on: eventLoop)
    }
}
