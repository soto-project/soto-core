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
        let provider = try self.credentialProvider(from: sharedCredentials, context: context, endpoint: endpoint)
        // Tag any error surfaced from this provider with the originating profile, so a failure
        // inside a credential chain (source profile, SSO source, STS AssumeRole, etc.) names
        // the profile the caller actually asked to resolve.
        return ProfileScopedCredentialProvider(inner: provider, profile: profile)
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
        #if os(macOS) || os(Linux)
        case .credentialProcess(let command):
            return CredentialProcessProvider(command: command)
        #endif
        }
    }
}

/// Wraps a credential provider so any error it raises is reported in terms of the profile
/// the caller asked to resolve. Without this, an error from a source profile, SSO source, or
/// STS AssumeRole call does not mention the profile that initiated the lookup.
struct ProfileScopedCredentialProvider: CredentialProvider {
    let inner: CredentialProvider
    let profile: String

    var description: String { "\(inner) (profile: \(profile))" }

    func getCredential(logger: Logger) async throws -> Credential {
        do {
            return try await self.inner.getCredential(logger: logger)
        } catch {
            throw ProfileCredentialError(profile: self.profile, underlying: error)
        }
    }

    func shutdown() async throws {
        try await self.inner.shutdown()
    }
}

/// Error thrown when credential resolution for a profile fails. Preserves the underlying
/// error so callers can still inspect the original cause.
public struct ProfileCredentialError: Error, CustomStringConvertible {
    /// The profile the caller asked to resolve.
    public let profile: String
    /// The error raised somewhere within the credential resolution for `profile`.
    public let underlying: any Error

    public init(profile: String, underlying: any Error) {
        self.profile = profile
        self.underlying = underlying
    }

    public var description: String {
        "Failed to resolve credentials for profile '\(self.profile)': \(self.underlying)"
    }
}
