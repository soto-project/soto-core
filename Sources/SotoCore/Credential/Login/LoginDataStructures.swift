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

// Login Configuration

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif

/// Error type for AWS Login credential operations
public struct AWSLoginCredentialError: Error, Equatable, CustomStringConvertible {
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

    /// Login session is missing from configuration
    public static var loginSessionMissing: AWSLoginCredentialError {
        AWSLoginCredentialError(code: "loginSessionMissing", message: "Login session is missing from configuration")
    }

    /// Region is missing from configuration
    public static var regionMissing: AWSLoginCredentialError {
        AWSLoginCredentialError(code: "regionMissing", message: "Region is missing from configuration")
    }

    /// Profile not found in configuration file
    public static func profileNotFound(_ profile: String) -> AWSLoginCredentialError {
        AWSLoginCredentialError(code: "profileNotFound", message: "Profile '\(profile)' not found in configuration file")
    }

    /// Configuration file not found at specified path
    public static func configFileNotFound(_ path: String) -> AWSLoginCredentialError {
        AWSLoginCredentialError(code: "configFileNotFound", message: "Configuration file not found at path: \(path)")
    }

    /// Token could not be loaded from disk
    public static func tokenLoadFailed(_ reason: String) -> AWSLoginCredentialError {
        AWSLoginCredentialError(code: "tokenLoadFailed", message: reason)
    }

    /// Token parsing failed
    public static var tokenParseFailed: AWSLoginCredentialError {
        AWSLoginCredentialError(code: "tokenParseFailed", message: "Failed to parse token data")
    }

    /// Endpoint URL construction failed
    public static var endpointConstructionFailed: AWSLoginCredentialError {
        AWSLoginCredentialError(code: "endpointConstructionFailed", message: "Failed to construct endpoint URL")
    }

    /// HTTP request failed
    public static func httpRequestFailed(_ reason: String) -> AWSLoginCredentialError {
        AWSLoginCredentialError(code: "httpRequestFailed", message: reason)
    }

    /// Token refresh operation failed
    public static func tokenRefreshFailed(_ reason: String) -> AWSLoginCredentialError {
        AWSLoginCredentialError(code: "tokenRefreshFailed", message: reason)
    }

    /// Invalid response received from server
    public static var invalidResponse: AWSLoginCredentialError {
        AWSLoginCredentialError(code: "invalidResponse", message: "Invalid response received from server")
    }

    /// Token write operation failed
    public static var tokenWriteFailed: AWSLoginCredentialError {
        AWSLoginCredentialError(code: "tokenWriteFailed", message: "Failed to write token to disk")
    }
}

struct LoginConfiguration {
    let endpoint: String
    let loginSession: String
    let region: Region
    let cacheDirectory: String?

    static let loginServiceHostPrefix = "signin"
    static let loginServiceName = "signin"
    static let loginEndpointPath = "/v1/token"
    static let cacheEnvVar = "AWS_LOGIN_CACHE_DIRECTORY"

    init(endpoint: String, loginSession: String, region: Region, cacheDirectory: String?) {
        self.endpoint = endpoint
        self.loginSession = loginSession
        self.region = region
        self.cacheDirectory = cacheDirectory
    }
}

struct LoginToken {
    let accessKeyId: String?
    let secretAccessKey: String?
    let sessionToken: String?
    let expiresAt: Date?
    let refreshToken: String
    let accountId: String
    let privateKey: String
    let publicKey: String
    let clientId: String
    let idToken: String

    init(
        accessKeyId: String? = nil,
        secretAccessKey: String? = nil,
        sessionToken: String? = nil,
        expiresAt: Date? = nil,
        refreshToken: String,
        accountId: String,
        privateKey: String,
        publicKey: String,
        clientId: String,
        idToken: String
    ) {
        self.accessKeyId = accessKeyId
        self.secretAccessKey = secretAccessKey
        self.sessionToken = sessionToken
        self.expiresAt = expiresAt
        self.refreshToken = refreshToken
        self.accountId = accountId
        self.privateKey = privateKey
        self.publicKey = publicKey
        self.clientId = clientId
        self.idToken = idToken
    }

    /// Create a new token with updated credentials
    func withUpdatedCredentials(
        accessKeyId: String,
        secretAccessKey: String,
        sessionToken: String,
        expiresAt: Date,
        refreshToken: String
    ) -> LoginToken {
        LoginToken(
            accessKeyId: accessKeyId,
            secretAccessKey: secretAccessKey,
            sessionToken: sessionToken,
            expiresAt: expiresAt,
            refreshToken: refreshToken,
            accountId: self.accountId,
            privateKey: self.privateKey,
            publicKey: self.publicKey,
            clientId: self.clientId,
            idToken: self.idToken
        )
    }
}
