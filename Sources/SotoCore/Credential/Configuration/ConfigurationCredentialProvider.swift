//===----------------------------------------------------------------------===//
//
// This source file is part of the Soto for AWS open source project
//
// Copyright (c) 2017-2026 the Soto project authors
// Licensed under Apache License v2.0
//
// See LICENSE.txt for license information
// See CONTRIBUTORS.txt for the list of Soto project authors
//
// SPDX-License-Identifier: Apache-2.0
//
//===----------------------------------------------------------------------===//

#if ConfigurationSupport

public import Configuration
public import NIOPosix

extension CredentialProviderFactory {
    /// Get credentials from a swift-configuration `ConfigReader`.
    ///
    /// Reads the standard AWS configuration keys from the supplied reader and selects a
    /// credential source in the same order as ``environment``:
    /// - Static credentials from `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY` and the
    ///   optional `AWS_SESSION_TOKEN`.
    /// - Web identity credentials from `AWS_ROLE_ARN`, `AWS_ROLE_SESSION_NAME`,
    ///   `AWS_WEB_IDENTITY_TOKEN_FILE` and `AWS_REGION`, assumed through STS.
    /// - ECS container credentials when `AWS_CONTAINER_CREDENTIALS_RELATIVE_URI` is set.
    ///
    /// A `ConfigReader` is built by the application at its entry point, so this provider has
    /// to be requested explicitly and is not part of ``default``. Any provider layered on the
    /// reader works, for example `EnvironmentVariablesProvider`, a file provider or a secrets
    /// manager.
    ///
    /// - Parameters:
    ///   - reader: The `ConfigReader` to read the AWS configuration keys from.
    ///   - endpoint: Optional STS endpoint override for the web identity path.
    ///   - retryPolicy: Retry policy for any requests to AWS services.
    ///   - threadPool: Thread pool used to load the web identity token file.
    public static func configuration(
        _ reader: ConfigReader,
        endpoint: String? = nil,
        retryPolicy: any RetryPolicy = .default,
        threadPool: NIOThreadPool = .singleton
    ) -> CredentialProviderFactory {
        .custom { context in
            // Static credentials.
            if let accessKeyId = reader.string(forKey: "AWS_ACCESS_KEY_ID"),
                let secretAccessKey = reader.string(forKey: "AWS_SECRET_ACCESS_KEY", isSecret: true)
            {
                return StaticCredentialProvider(
                    accessKeyId: accessKeyId,
                    secretAccessKey: secretAccessKey,
                    sessionToken: reader.string(forKey: "AWS_SESSION_TOKEN", isSecret: true)
                )
            }

            // Web identity credentials assumed through STS.
            if let roleArn = reader.string(forKey: "AWS_ROLE_ARN"),
                let roleSessionName = reader.string(forKey: "AWS_ROLE_SESSION_NAME"),
                let webIdentityTokenFile = reader.string(forKey: "AWS_WEB_IDENTITY_TOKEN_FILE")
            {
                let region = reader.string(forKey: "AWS_REGION").flatMap(Region.init(awsRegionName:)) ?? .useast1
                let provider = STSAssumeRoleCredentialProvider(
                    roleArn: roleArn,
                    roleSessionName: roleSessionName,
                    webIdentityTokenFile: webIdentityTokenFile,
                    region: region,
                    retryPolicy: retryPolicy,
                    httpClient: context.httpClient,
                    endpoint: endpoint,
                    threadPool: threadPool
                )
                return RotatingCredentialProvider(context: context, provider: provider)
            }

            // ECS container credentials.
            if let relativeURI = reader.string(forKey: "AWS_CONTAINER_CREDENTIALS_RELATIVE_URI") {
                let provider = ECSMetaDataClient(httpClient: context.httpClient, relativeURL: relativeURI)
                return RotatingCredentialProvider(context: context, provider: provider)
            }

            return NullCredentialProvider()
        }
    }
}

#endif  // ConfigurationSupport
