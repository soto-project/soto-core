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

import struct Foundation.UUID
import Logging
import NIO
import NIOConcurrencyHelpers
import SotoSignerV4

class ConfigFileCredentialProvider: CredentialProviderSelector {
    /// promise to find a credential provider
    let startupPromise: EventLoopPromise<CredentialProvider>
    /// lock for access to _internalProvider.
    let lock = Lock()
    /// internal version of internal provider. Should access this through `internalProvider`
    var _internalProvider: CredentialProvider?

    init(credentialsFilePath: String, configFilePath: String? = nil, profile: String? = nil, context: CredentialProviderFactory.Context) {
        startupPromise = context.eventLoop.makePromise(of: CredentialProvider.self)
        startupPromise.futureResult.whenSuccess { result in
            self.internalProvider = result
        }

        let profile = profile ?? Environment["AWS_PROFILE"] ?? ConfigFileLoader.defaultProfile
        Self.sharedCredentials(from: credentialsFilePath, configFilePath: configFilePath, for: profile, context: context)
            .cascade(to: self.startupPromise)
    }

    /// Load shared credentials and profile configuration
    ///
    /// - Parameters:
    ///   - credentialsByteBuffer: contents of AWS shared credentials file (usually `~/.aws/credentials`
    ///   - configByteBuffer: contents of AWS profile configuration file (usually `~/.aws/config`
    ///   - profile: named profile to load (usually `default`)
    ///   - context: credential provider factory context
    /// - Returns: Credential Provider (StaticCredentials or STSAssumeRole)
    static func sharedCredentials(
        from credentialsFilePath: String,
        configFilePath: String? = nil,
        for profile: String,
        context: CredentialProviderFactory.Context
    ) -> EventLoopFuture<CredentialProvider> {
        return ConfigFileLoader.loadSharedCredentials(
            credentialsFilePath: credentialsFilePath,
            configFilePath: configFilePath,
            profile: profile,
            context: context
        )
        .flatMap { credentials, config in
            return context.eventLoop.makeSucceededFuture(sharedCredentials(from: credentials, config: config, for: profile, context: context))
        }
    }

    /// Generate credential provider based on shared credentials and profile configuration
    ///
    /// Credentials file settings have precedence over profile configuration settings
    /// https://docs.aws.amazon.com/cli/latest/userguide/cli-configure-quickstart.html#cli-configure-quickstart-precedence
    ///
    /// - Parameters:
    ///   - credentialsBuffer: contents of AWS shared credentials file (usually `~/.aws/credentials`
    ///   - configByteBuffer: contents of AWS profile configuration file (usually `~/.aws/config`
    ///   - profile: named profile to load (usually `default`)
    ///   - context: credential provider factory context
    /// - Returns: Credential Provider (StaticCredentials or STSAssumeRole)
    static func sharedCredentials(
        from credentials: ConfigFileLoader.ProfileCredentials,
        config: ConfigFileLoader.ProfileConfig?,
        for profile: String,
        context: CredentialProviderFactory.Context
    ) -> CredentialProvider {
        let staticCredential = StaticCredential(
            accessKeyId: credentials.accessKey,
            secretAccessKey: credentials.secretAccessKey,
            sessionToken: credentials.sessionToken
        )

        // If `role_arn` and `sourcer_profile` are defined, temporary credentials must be loaded via STS Assume Role operation
        if let roleArn = credentials.roleArn ?? config?.roleArn,
           let _ = credentials.sourceProfile ?? config?.sourceProfile
        {
            // Proceed with STSAssumeRole operation
            let sessionName = credentials.roleSessionName ?? config?.roleSessionName ?? UUID().uuidString
            let request = STSAssumeRoleRequest(roleArn: roleArn, roleSessionName: sessionName)
            let region = config?.region ?? .useast1
            let provider = STSAssumeRoleCredentialProvider(request: request, credentialProvider: .default, region: region, httpClient: context.httpClient)
            return RotatingCredentialProvider(context: context, provider: provider)
        }

        // If `role_arn` and `credental_source` are defined, temporary credentials must be loaded from source
        if let _ = credentials.roleArn ?? config?.roleArn,
           let _ = credentials.credentialSource ?? config?.credentialSource
        {
            fatalError("'credential_source' setting not yet supported")
        }

        // Return static credentials
        return staticCredential
    }
}
