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

// SSO Configuration, Token, and Error Types

import struct Foundation.CharacterSet
import struct Foundation.Data
import struct Foundation.Date
import class Foundation.ISO8601DateFormatter
import class Foundation.JSONDecoder
import class Foundation.JSONEncoder
import struct Foundation.TimeInterval
import struct Foundation.URL

// MARK: - SSO Configuration

struct SSOConfiguration {
    /// SSO start URL (e.g., https://d-90678022de.awsapps.com/start)
    let ssoStartUrl: String
    /// Region for SSO service
    let ssoRegion: Region
    /// AWS account ID
    let ssoAccountId: String
    /// IAM role name
    let ssoRoleName: String
    /// Target region for credentials (optional)
    let region: Region?
    /// Session name for modern format (enables refresh)
    let sessionName: String?
}

// MARK: - SSO Token (cache file format)

struct SSOToken: Codable {
    /// OAuth access token
    let accessToken: String
    /// ISO8601 date string for expiration
    let expiresAt: String
    /// For token refresh (modern format only)
    let refreshToken: String?
    /// OAuth client ID (modern format only)
    let clientId: String?
    /// OAuth client secret (modern format only)
    let clientSecret: String?
    /// Client registration expiry (modern format only)
    let registrationExpiresAt: String?
    /// SSO start URL
    let startUrl: String?
    /// SSO region
    let region: String?
}

// MARK: - SSO-OIDC CreateToken Response

struct CreateTokenResponse: Codable {
    let accessToken: String
    let expiresIn: Int
    let tokenType: String?
    let refreshToken: String?
}

// MARK: - SSO GetRoleCredentials Response

struct SSOGetRoleCredentialsResponse: Codable {
    let roleCredentials: SSORoleCredentials
}

struct SSORoleCredentials: Codable {
    let accessKeyId: String
    let secretAccessKey: String
    let sessionToken: String
    /// Unix timestamp in milliseconds
    let expiration: Int64
}

// MARK: - SSO Credential Error

/// Error type for AWS SSO credential operations
public struct AWSSSOCredentialError: Error, Equatable, CustomStringConvertible {
    /// Error code identifying the type of error
    public let code: String
    /// Human-readable error message
    public let message: String

    private init(code: String, message: String) {
        self.code = code
        self.message = message
    }

    public var description: String {
        "\(code): \(message)"
    }

    // MARK: - Predefined Error Types

    /// Configuration file not found at specified path
    public static func configFileNotFound(_ path: String) -> AWSSSOCredentialError {
        AWSSSOCredentialError(code: "configFileNotFound", message: "Configuration file not found at path: \(path)")
    }

    /// Profile not found in configuration file
    public static func profileNotFound(_ profile: String) -> AWSSSOCredentialError {
        AWSSSOCredentialError(code: "profileNotFound", message: "Profile '\(profile)' not found in configuration file")
    }

    /// Profile missing SSO configuration
    public static func ssoConfigMissing(_ profile: String) -> AWSSSOCredentialError {
        AWSSSOCredentialError(
            code: "ssoConfigMissing",
            message: "Profile '\(profile)' does not have SSO configuration. Configure with 'aws configure sso'."
        )
    }

    /// Referenced sso-session not found in config
    public static func ssoSessionNotFound(_ sessionName: String) -> AWSSSOCredentialError {
        AWSSSOCredentialError(code: "ssoSessionNotFound", message: "SSO session '\(sessionName)' not found in ~/.aws/config")
    }

    /// Token cache file not found - user needs to run 'aws sso login'
    public static func tokenCacheNotFound(_ profile: String) -> AWSSSOCredentialError {
        AWSSSOCredentialError(
            code: "tokenCacheNotFound",
            message: "SSO token not found. Run 'aws sso login --profile \(profile)' to authenticate."
        )
    }

    /// Access token expired, no refresh token available
    public static func tokenExpired(_ profile: String) -> AWSSSOCredentialError {
        AWSSSOCredentialError(
            code: "tokenExpired",
            message: "SSO token expired. Run 'aws sso login --profile \(profile)' to re-authenticate."
        )
    }

    /// Token refresh API call failed
    public static func tokenRefreshFailed(_ reason: String) -> AWSSSOCredentialError {
        AWSSSOCredentialError(code: "tokenRefreshFailed", message: reason)
    }

    /// OAuth client registration expired
    public static func clientRegistrationExpired(_ profile: String) -> AWSSSOCredentialError {
        AWSSSOCredentialError(
            code: "clientRegistrationExpired",
            message: "OAuth client registration expired. Run 'aws sso login --profile \(profile)' to re-register."
        )
    }

    /// Corrupted cache file
    public static func invalidTokenFormat(_ reason: String) -> AWSSSOCredentialError {
        AWSSSOCredentialError(code: "invalidTokenFormat", message: reason)
    }

    /// SSO GetRoleCredentials API error
    public static func getRoleCredentialsFailed(_ reason: String) -> AWSSSOCredentialError {
        AWSSSOCredentialError(code: "getRoleCredentialsFailed", message: reason)
    }
}
