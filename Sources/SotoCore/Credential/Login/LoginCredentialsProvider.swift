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

// Login Credentials Provider - Main Provider

import Foundation
import Logging
import NIOCore
import NIOFoundationCompat
import NIOPosix
import SotoSignerV4

// MARK: - Login Credentials Provider

@available(macOS 13.0, iOS 14.0, tvOS 14.0, watchOS 7.0, *)
public struct LoginCredentialsProvider: CredentialProvider {
    private let configuration: LoginConfiguration
    private let dpopGenerator = DPoPTokenGenerator()
    private let httpClient: AWSHTTPClient
    private let threadPool: NIOThreadPool

    init(configuration: LoginConfiguration, httpClient: AWSHTTPClient, threadPool: NIOThreadPool = .singleton) {
        self.configuration = configuration
        self.httpClient = httpClient
        self.threadPool = threadPool
    }

    public func getCredential(logger: Logger) async throws -> Credential {
        // Load token from disk
        let tokenFileManager = TokenFileManager()
        let tokenPath = try tokenFileManager.constructTokenPath(
            loginSession: configuration.loginSession,
            cacheDirectory: configuration.cacheDirectory
        )

        let fileIO = NonBlockingFileIO(threadPool: threadPool)
        let token = try await tokenFileManager.loadToken(from: tokenPath, fileIO: fileIO)

        // Check if token is still valid per spec
        if let expiresAt = token.expiresAt, expiresAt > Date() {
            // Token is still valid, return cached credentials
            guard let accessKeyId = token.accessKeyId,
                let secretAccessKey = token.secretAccessKey,
                let sessionToken = token.sessionToken
            else {
                throw AWSLoginCredentialError.tokenLoadFailed("Token missing credentials")
            }

            logger.trace("Returning cached credentials")
            return RotatingCredential(
                accessKeyId: accessKeyId,
                secretAccessKey: secretAccessKey,
                sessionToken: sessionToken,
                expiration: expiresAt
            )
        }

        logger.trace("Credentials expired - refreshing")

        // Token expired or missing, refresh it
        return try await refreshToken(tokenPath: tokenPath, logger: logger)
    }

    private func refreshToken(tokenPath: String, logger: Logger) async throws -> Credential {
        // MUST reload token from disk before refreshing per spec
        // This ensures we don't refresh if another process already did
        let tokenFileManager = TokenFileManager()
        let fileIO = NonBlockingFileIO(threadPool: threadPool)
        let reloadedToken = try await tokenFileManager.loadToken(from: tokenPath, fileIO: fileIO)

        // Check again if it was refreshed by another process
        if let expiresAt = reloadedToken.expiresAt, expiresAt > Date() {
            guard let accessKeyId = reloadedToken.accessKeyId,
                let secretAccessKey = reloadedToken.secretAccessKey,
                let sessionToken = reloadedToken.sessionToken
            else {
                throw AWSLoginCredentialError.tokenLoadFailed("Token missing credentials")
            }

            return RotatingCredential(
                accessKeyId: accessKeyId,
                secretAccessKey: secretAccessKey,
                sessionToken: sessionToken,
                expiration: expiresAt
            )
        }

        // Proceed with refresh
        let token = reloadedToken

        // Create request body
        let requestBody = TokenRequest(
            clientId: token.clientId,
            refreshToken: token.refreshToken,
            grantType: "refresh_token"
        )
        let encoder = JSONEncoder()
        let bodyData = try encoder.encode(requestBody)

        // Construct endpoint URL
        let endpointURL = "https://\(configuration.endpoint)\(LoginConfiguration.loginEndpointPath)"
        guard let url = URL(string: endpointURL) else {
            throw AWSLoginCredentialError.endpointConstructionFailed
        }

        // Generate DPoP header
        let dpopHeader = try dpopGenerator.generateDPoPHeader(
            endpoint: endpointURL,
            httpMethod: "POST",
            pemKey: token.privateKey
        )

        // Create HTTP request using AWSHTTPClient
        var headers = HTTPHeaders()
        headers.add(name: "Content-Type", value: "application/json")
        headers.add(name: "DPoP", value: dpopHeader)
        // Extract host from endpoint (remove protocol if present)
        let host = configuration.endpoint
            .replacing("https://", with: "")
            .replacing("http://", with: "")
        headers.add(name: "Host", value: host)
        headers.add(name: "Content-Length", value: "\(bodyData.count)")

        let request = AWSHTTPRequest(
            url: url,
            method: .POST,
            headers: headers,
            body: .init(bytes: bodyData)
        )

        // Execute request
        let response = try await httpClient.execute(
            request: request,
            timeout: .seconds(30),
            logger: logger
        )

        guard (200...299).contains(response.status.code) else {
            // Try to parse error response per spec
            let body = try? await response.body.collect(upTo: 1024 * 10)
            if let body,
                let errorResponse = try? JSONDecoder().decode(ErrorResponse.self, from: Data(buffer: body))
            {
                // Handle specific error cases per spec
                switch errorResponse.error {
                case "TOKEN_EXPIRED":
                    throw AWSLoginCredentialError.tokenRefreshFailed("Your session has expired. Please reauthenticate with `aws login`.")
                case "USER_CREDENTIALS_CHANGED":
                    throw AWSLoginCredentialError.tokenRefreshFailed(
                        "Unable to refresh credentials because of a change in your password. Please reauthenticate with your new password."
                    )
                case "INSUFFICIENT_PERMISSIONS":
                    throw AWSLoginCredentialError.tokenRefreshFailed(
                        "Unable to refresh credentials due to insufficient permissions. You may be missing permission for the 'signin:CreateOAuth2Token' action."
                    )
                default:
                    throw AWSLoginCredentialError.httpRequestFailed(
                        "HTTP status: \(response.status.code), error: \(errorResponse.error), message: \(errorResponse.message)"
                    )
                }
            }

            throw AWSLoginCredentialError.httpRequestFailed("HTTP status: \(response.status.code)")
        }

        // Collect response body
        let body = try await response.body.collect(upTo: 1024 * 1024)
        guard body.readableBytes > 0 else {
            throw AWSLoginCredentialError.httpRequestFailed("Empty response body")
        }

        // Parse response
        let decoder = JSONDecoder()
        let tokenResponse = try decoder.decode(TokenResponse.self, from: Data(buffer: body))

        // Calculate expiration time from expiresIn (seconds from now)
        let expiresAt = Date(timeIntervalSinceNow: TimeInterval(tokenResponse.expiresIn))

        // Create new token with updated credentials
        let updatedToken = token.withUpdatedCredentials(
            accessKeyId: tokenResponse.accessToken.accessKeyId,
            secretAccessKey: tokenResponse.accessToken.secretAccessKey,
            sessionToken: tokenResponse.accessToken.sessionToken,
            expiresAt: expiresAt,
            refreshToken: tokenResponse.refreshToken
        )

        // Save updated token to disk
        try await tokenFileManager.saveToken(updatedToken, to: tokenPath, fileIO: fileIO)

        // Return expiring credential
        return RotatingCredential(
            accessKeyId: tokenResponse.accessToken.accessKeyId,
            secretAccessKey: tokenResponse.accessToken.secretAccessKey,
            sessionToken: tokenResponse.accessToken.sessionToken,
            expiration: expiresAt
        )
    }
}

// MARK: - Initializers

@available(macOS 13.0, iOS 14.0, tvOS 14.0, watchOS 7.0, *)
extension LoginCredentialsProvider {
    /// Create a LoginCredentialsProvider from profile configuration
    /// - Parameters:
    ///   - profileName: Name of the profile in ~/.aws/config (defaults to "default")
    ///   - cacheDirectoryOverride: Optional override for token cache directory
    ///   - httpClient: HTTP client for making requests
    /// - Throws: AWSLoginCredentialError if configuration cannot be loaded
    public init(
        profileName: String? = nil,
        cacheDirectoryOverride: String? = nil,
        httpClient: AWSHTTPClient
    ) throws {
        let loader = ProfileConfigurationLoader()
        let configuration = try loader.loadConfiguration(
            profileName: profileName,
            cacheDirectoryOverride: cacheDirectoryOverride
        )

        self.init(
            configuration: configuration,
            httpClient: httpClient
        )
    }
}

// MARK: - CredentialProviderFactory Extension

extension CredentialProviderFactory {
    /// Use AWS Login credentials provider
    ///
    /// This provider uses AWS Login session tokens to obtain temporary credentials.
    /// Credentials are automatically rotated when they expire.
    ///
    /// - Parameters:
    ///   - profileName: Name of the profile in ~/.aws/config (defaults to "default")
    ///   - cacheDirectoryOverride: Optional override for token cache directory
    /// - Returns: A credential provider factory
    @available(macOS 13.0, iOS 14.0, tvOS 14.0, watchOS 7.0, *)
    public static func login(
        profileName: String? = nil,
        cacheDirectoryOverride: String? = nil
    ) -> CredentialProviderFactory {
        .custom { context in
            guard
                let provider = try? LoginCredentialsProvider(
                    profileName: profileName,
                    cacheDirectoryOverride: cacheDirectoryOverride,
                    httpClient: context.httpClient
                )
            else {
                return NullCredentialProvider()
            }
            // Wrap in RotatingCredentialProvider for automatic credential rotation
            return RotatingCredentialProvider(context: context, provider: provider)
        }
    }
}

// MARK: - HTTP Request/Response Models

private struct TokenRequest: Codable {
    let clientId: String
    let refreshToken: String
    let grantType: String
}

private struct AccessTokenResponse: Codable {
    let accessKeyId: String
    let secretAccessKey: String
    let sessionToken: String
}

private struct TokenResponse: Codable {
    let accessToken: AccessTokenResponse
    let tokenType: String
    let expiresIn: Int
    let refreshToken: String
}

private struct ErrorResponse: Codable {
    let error: String
    let message: String
}
