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
import NIOConcurrencyHelpers
import NIOCore
import NIOPosix
import SotoSignerV4

final class ConfigFileCredentialProvider: CredentialProviderSelector {
    private let getProviderTask: Task<CredentialProvider, Error>
    init(
        credentialsFilePath: String,
        configFilePath: String,
        profile: String? = nil,
        context: CredentialProviderFactory.Context,
        endpoint: String? = nil
    ) {
        self.getProviderTask = Task {
            let profile = profile ?? Environment["AWS_PROFILE"] ?? ConfigFileLoader.defaultProfile
            return try await ConfigFileCredentialProvider.credentialProvider(
                from: credentialsFilePath,
                configFilePath: configFilePath,
                for: profile,
                context: context,
                endpoint: endpoint
            )
        }
    }

    func getCredentialProviderTask() async throws -> CredentialProvider {
        try await self.getProviderTask.value
    }

    func cancelCredentialProviderTask() {
        self.getProviderTask.cancel()
    }

    /// Credential provider from shared credentials and profile configuration files
    ///
    /// - Parameters:
    ///   - credentialsByteBuffer: contents of AWS shared credentials file (usually `~/.aws/credentials`)
    ///   - configByteBuffer: contents of AWS profile configuration file (usually `~/.aws/config`)
    ///   - profile: named profile to load (usually `default`)
    ///   - context: credential provider factory context
    ///   - endpoint: STS Assume role endpoint (for unit testing)
    /// - Returns: Credential Provider (StaticCredentials or STSAssumeRole)
    static func credentialProvider(
        from credentialsFilePath: String,
        configFilePath: String,
        for profile: String,
        context: CredentialProviderFactory.Context,
        endpoint: String?,
        threadPool: NIOThreadPool = .singleton
    ) async throws -> CredentialProvider {
        let sharedCredentials = try await ConfigFileLoader.loadSharedCredentials(
            credentialsFilePath: credentialsFilePath,
            configFilePath: configFilePath,
            profile: profile,
            threadPool: threadPool
        )
        return try self.credentialProvider(from: sharedCredentials, context: context, endpoint: endpoint)
    }

    /// Generate credential provider based on shared credentials and profile configuration
    ///
    /// Credentials file settings have precedence over profile configuration settings
    /// https://docs.aws.amazon.com/cli/latest/userguide/cli-configure-quickstart.html#cli-configure-quickstart-precedence
    ///
    /// - Parameters:
    ///   - sharedCredentials: combined credentials loaded from disl (usually `~/.aws/credentials` and `~/.aws/config`)
    ///   - context: credential provider factory context
    ///   - endpoint: STS Assume role endpoint (for unit testing)
    /// - Returns: Credential Provider (StaticCredentials or STSAssumeRole)
    static func credentialProvider(
        from sharedCredentials: ConfigFileLoader.SharedCredentials,
        context: CredentialProviderFactory.Context,
        endpoint: String?
    ) throws -> CredentialProvider {
        switch sharedCredentials {
        case .staticCredential(let staticCredential):
            return staticCredential
        case .assumeRole(let roleArn, let sessionName, let region, let sourceCredentialProvider):
            let region = region ?? .useast1
            return STSAssumeRoleCredentialProvider(
                roleArn: roleArn,
                roleSessionName: sessionName,
                credentialProvider: sourceCredentialProvider,
                region: region,
                httpClient: context.httpClient,
                endpoint: endpoint
            )
        }
    }
}
