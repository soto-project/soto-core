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

// SSO Credential Provider - Main Provider

import INIParser
import Logging
import NIOCore
import NIOFoundationCompat
import NIOPosix
import SotoSignerV4

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif

// MARK: - SSO Credential Provider

public struct SSOCredentialProvider: CredentialProvider {
    private let configuration: SSOConfiguration?
    private let profileName: String?
    private let configPath: String?
    private let httpClient: AWSHTTPClient
    private let threadPool: NIOThreadPool

    /// Create an SSOCredentialProvider with explicit configuration (for testing)
    init(configuration: SSOConfiguration, httpClient: AWSHTTPClient, threadPool: NIOThreadPool = .singleton) {
        self.configuration = configuration
        self.profileName = nil
        self.configPath = nil
        self.httpClient = httpClient
        self.threadPool = threadPool
    }

    /// Create an SSOCredentialProvider with explicit config file path (for testing)
    init(
        profileName: String? = nil,
        configPath: String,
        httpClient: AWSHTTPClient,
        threadPool: NIOThreadPool = .singleton
    ) {
        self.configuration = nil
        self.profileName = profileName
        self.configPath = configPath
        self.httpClient = httpClient
        self.threadPool = threadPool
    }

    /// Create an SSOCredentialProvider from profile configuration
    /// - Parameters:
    ///   - profileName: Name of the profile in ~/.aws/config (defaults to "default")
    ///   - httpClient: HTTP client for making requests
    public init(
        profileName: String? = nil,
        httpClient: AWSHTTPClient
    ) {
        self.configuration = nil
        self.profileName = profileName
        self.configPath = nil
        self.httpClient = httpClient
        self.threadPool = .singleton
    }

    public func getCredential(logger: Logger) async throws -> Credential {
        let profile = profileName ?? "default"
        let config = try await getConfiguration()
        let tokenManager = SSOTokenManager(httpClient: httpClient)
        let fileIO = NonBlockingFileIO(threadPool: threadPool)

        // Construct token cache path
        let tokenPath = try tokenManager.constructTokenPath(config: config)

        // Load token from cache (with automatic refresh if modern format)
        let token = try await tokenManager.getToken(
            from: tokenPath,
            config: config,
            profileName: profile,
            fileIO: fileIO,
            threadPool: threadPool,
            logger: logger
        )

        // Call SSO GetRoleCredentials API
        let credentials = try await getRoleCredentials(
            accessToken: token.accessToken,
            accountId: config.ssoAccountId,
            roleName: config.ssoRoleName,
            region: config.ssoRegion,
            logger: logger
        )

        // Return expiring credential
        let expirationDate = Date(timeIntervalSince1970: TimeInterval(credentials.expiration / 1000))
        return RotatingCredential(
            accessKeyId: credentials.accessKeyId,
            secretAccessKey: credentials.secretAccessKey,
            sessionToken: credentials.sessionToken,
            expiration: expirationDate
        )
    }

    // MARK: - Configuration Loading

    private func getConfiguration() async throws -> SSOConfiguration {
        if let configuration = configuration {
            return configuration
        }
        return try await loadConfiguration(profileName: profileName, configPath: configPath)
    }

    private func loadConfiguration(
        profileName: String? = nil,
        configPath: String? = nil
    ) async throws -> SSOConfiguration {
        let profile = profileName ?? "default"
        let path = configPath ?? ConfigFileLoader.defaultProfileConfigPath

        // Load INI file using ConfigFileLoader
        let fileIO = NonBlockingFileIO(threadPool: .singleton)
        let parser: INIParser
        do {
            parser = try await ConfigFileLoader.loadINIFile(path: path, fileIO: fileIO)
        } catch {
            throw AWSSSOCredentialError.configFileNotFound(path)
        }

        // Look for profile section
        let profileKey = profile == "default" ? profile : "profile \(profile)"
        guard let profileSection = parser.sections[profileKey] else {
            throw AWSSSOCredentialError.profileNotFound(profile)
        }

        // Check for sso_session (modern format) or direct SSO fields (legacy format)
        if let ssoSessionName = profileSection["sso_session"] {
            // Modern format: Load from sso-session section
            return try loadModernSSOConfig(
                profileSection: profileSection,
                ssoSessionName: ssoSessionName,
                parser: parser,
                profile: profile
            )
        } else {
            // Legacy format: Load directly from profile
            return try loadLegacySSOConfig(
                profileSection: profileSection,
                profile: profile
            )
        }
    }

    private func loadModernSSOConfig(
        profileSection: [String: String],
        ssoSessionName: String,
        parser: INIParser,
        profile: String
    ) throws -> SSOConfiguration {
        // Load sso-session section
        let sessionKey = "sso-session \(ssoSessionName)"
        guard let sessionSection = parser.sections[sessionKey] else {
            throw AWSSSOCredentialError.ssoSessionNotFound(ssoSessionName)
        }

        // Required fields from sso-session
        guard let ssoStartUrl = sessionSection["sso_start_url"] else {
            throw AWSSSOCredentialError.ssoConfigMissing(profile)
        }
        guard let ssoRegionString = sessionSection["sso_region"] else {
            throw AWSSSOCredentialError.ssoConfigMissing(profile)
        }

        // Required fields from profile
        guard let ssoAccountId = profileSection["sso_account_id"] else {
            throw AWSSSOCredentialError.ssoConfigMissing(profile)
        }
        guard let ssoRoleName = profileSection["sso_role_name"] else {
            throw AWSSSOCredentialError.ssoConfigMissing(profile)
        }

        let region = profileSection["region"].map { Region(rawValue: $0) }

        return SSOConfiguration(
            ssoStartUrl: ssoStartUrl,
            ssoRegion: Region(rawValue: ssoRegionString),
            ssoAccountId: ssoAccountId,
            ssoRoleName: ssoRoleName,
            region: region,
            sessionName: ssoSessionName
        )
    }

    private func loadLegacySSOConfig(
        profileSection: [String: String],
        profile: String
    ) throws -> SSOConfiguration {
        guard let ssoStartUrl = profileSection["sso_start_url"] else {
            throw AWSSSOCredentialError.ssoConfigMissing(profile)
        }
        guard let ssoRegionString = profileSection["sso_region"] else {
            throw AWSSSOCredentialError.ssoConfigMissing(profile)
        }
        guard let ssoAccountId = profileSection["sso_account_id"] else {
            throw AWSSSOCredentialError.ssoConfigMissing(profile)
        }
        guard let ssoRoleName = profileSection["sso_role_name"] else {
            throw AWSSSOCredentialError.ssoConfigMissing(profile)
        }

        let region = profileSection["region"].map { Region(rawValue: $0) }

        return SSOConfiguration(
            ssoStartUrl: ssoStartUrl,
            ssoRegion: Region(rawValue: ssoRegionString),
            ssoAccountId: ssoAccountId,
            ssoRoleName: ssoRoleName,
            region: region,
            sessionName: nil
        )
    }

    // MARK: - SSO GetRoleCredentials API

    private func getRoleCredentials(
        accessToken: String,
        accountId: String,
        roleName: String,
        region: Region,
        logger: Logger
    ) async throws -> SSORoleCredentials {
        let endpoint = "portal.sso.\(region.rawValue).amazonaws.com"

        // Build query string manually (cross-platform safe)
        let query =
            "role_name=\(RequestEncodingContainer.urlEncodeQueryParam(roleName))&account_id=\(RequestEncodingContainer.urlEncodeQueryParam(accountId))"
        let urlString = "https://\(endpoint)/federation/credentials?\(query)"

        guard let url = URL(string: urlString) else {
            throw AWSSSOCredentialError.getRoleCredentialsFailed("Failed to construct SSO GetRoleCredentials URL")
        }

        var headers = HTTPHeaders()
        headers.add(name: "x-amz-sso_bearer_token", value: accessToken)
        headers.add(name: "Accept", value: "application/json")
        headers.add(name: "Host", value: endpoint)

        let request = AWSHTTPRequest(
            url: url,
            method: .GET,
            headers: headers,
            body: .init()
        )

        let response = try await httpClient.execute(request: request, timeout: .seconds(30), logger: logger)

        guard (200...299).contains(response.status.code) else {
            throw AWSSSOCredentialError.getRoleCredentialsFailed(
                "HTTP \(response.status.code): Failed to get SSO credentials"
            )
        }

        let body = try await response.body.collect(upTo: 1024 * 1024)
        let decoder = JSONDecoder()
        let apiResponse = try decoder.decode(SSOGetRoleCredentialsResponse.self, from: body)

        return apiResponse.roleCredentials
    }

}

// MARK: - CredentialProviderFactory Extension

extension CredentialProviderFactory {
    /// Use AWS IAM Identity Center (SSO) credential provider
    ///
    /// This provider uses cached SSO session tokens to obtain temporary AWS credentials.
    /// Users must authenticate with `aws sso login` before using this provider.
    ///
    /// Automatic token refresh:
    /// - Modern sso-session format: Automatically refreshes expired tokens using OAuth refresh tokens
    /// - Legacy format: Requires manual re-authentication with `aws sso login`
    ///
    /// - Parameters:
    ///   - profileName: Name of the profile in ~/.aws/config (defaults to "default")
    /// - Returns: A credential provider factory
    public static func sso(
        profileName: String? = nil
    ) -> CredentialProviderFactory {
        .custom { context in
            let provider = SSOCredentialProvider(
                profileName: profileName,
                httpClient: context.httpClient
            )
            // Wrap in RotatingCredentialProvider for automatic credential rotation
            return RotatingCredentialProvider(context: context, provider: provider)
        }
    }
}
