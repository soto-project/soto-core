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

// SSO Token Cache Management - Disk I/O and Token Refresh

import Crypto
import Logging
import NIOCore
import NIOFoundationCompat
import NIOPosix

#if canImport(Glibc)
import Glibc
#elseif canImport(Musl)
import Musl
#elseif canImport(Darwin)
import Darwin.C
#elseif canImport(Android)
import Android
#else
#error("Unsupported platform")
#endif

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif

struct SSOTokenManager {
    private let httpClient: AWSHTTPClient

    /// Refresh window: start refreshing when token expires in less than 15 minutes (same as botocore)
    let refreshWindow: TimeInterval = 15 * 60

    init(httpClient: AWSHTTPClient) {
        self.httpClient = httpClient
    }

    // MARK: - Token Path Construction

    /// Construct the path to the cached SSO token file.
    /// The filename is the SHA-1 hash of the cache key, hex-encoded, with .json extension.
    /// - For modern format: cache key is the session name
    /// - For legacy format: cache key is the SSO start URL
    func constructTokenPath(config: SSOConfiguration) throws -> String {
        guard let homeDir = ProcessInfo.processInfo.environment["HOME"] else {
            throw AWSSSOCredentialError.invalidTokenFormat("Cannot determine HOME directory")
        }
        let baseDir = "\(homeDir)/.aws/sso/cache"

        // Modern format uses session name as cache key, legacy uses start URL
        let cacheKey = config.sessionName ?? config.ssoStartUrl
        let keyData = Data(cacheKey.utf8)
        let hash = Insecure.SHA1.hash(data: keyData)
        let hashString = hash.compactMap { String(format: "%02x", $0) }.joined()

        return "\(baseDir)/\(hashString).json"
    }

    // MARK: - Token Loading

    func loadToken(from path: String, profileName: String, fileIO: NonBlockingFileIO) async throws -> SSOToken {
        let byteBuffer: ByteBuffer
        do {
            byteBuffer = try await fileIO.withFileRegion(path: path) { fileRegion in
                try await fileIO.read(
                    fileHandle: fileRegion.fileHandle,
                    byteCount: fileRegion.readableBytes,
                    allocator: ByteBufferAllocator()
                )
            }
        } catch {
            throw AWSSSOCredentialError.tokenCacheNotFound(profileName)
        }

        guard let data = byteBuffer.getData(at: 0, length: byteBuffer.readableBytes) else {
            throw AWSSSOCredentialError.invalidTokenFormat("Cannot read token data from \(path)")
        }

        let decoder = JSONDecoder()
        guard let token = try? decoder.decode(SSOToken.self, from: data) else {
            throw AWSSSOCredentialError.invalidTokenFormat("Failed to parse SSO token JSON at \(path)")
        }

        return token
    }

    // MARK: - Token Saving

    func saveToken(_ token: SSOToken, to path: String, fileIO: NonBlockingFileIO, threadPool: NIOThreadPool) async throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted
        let data = try encoder.encode(token)

        var buffer = ByteBufferAllocator().buffer(capacity: data.count)
        buffer.writeBytes(data)

        // Delete file if it exists to ensure clean write
        _ = try? await threadPool.runIfActive { unlink(path) }

        try await fileIO.withFileHandle(
            path: path,
            mode: .write,
            flags: .allowFileCreation(posixMode: 0o600)
        ) { fileHandle in
            try await fileIO.write(fileHandle: fileHandle, buffer: buffer)
        }
    }

    // MARK: - Token Retrieval with Refresh

    /// Get a valid SSO token, refreshing if needed (modern format only).
    func getToken(
        from tokenPath: String,
        config: SSOConfiguration,
        profileName: String,
        fileIO: NonBlockingFileIO,
        threadPool: NIOThreadPool,
        logger: Logger
    ) async throws -> SSOToken {
        var token = try await loadToken(from: tokenPath, profileName: profileName, fileIO: fileIO)

        // Parse expiration (try with fractional seconds first, then without)
        guard let expiration = Self.parseISO8601Date(token.expiresAt) else {
            throw AWSSSOCredentialError.invalidTokenFormat("Invalid expiresAt date format: \(token.expiresAt)")
        }

        // Check if token needs refresh (within 15 min window)
        if expiration.timeIntervalSinceNow < self.refreshWindow {
            // Check if we have refresh capability (modern format)
            guard let refreshToken = token.refreshToken,
                let clientId = token.clientId,
                let clientSecret = token.clientSecret
            else {
                // Legacy format or missing refresh fields - cannot refresh
                guard expiration > Date() else {
                    throw AWSSSOCredentialError.tokenExpired(profileName)
                }
                // Token hasn't actually expired yet, just within refresh window
                return token
            }

            // Check client registration hasn't expired
            if let regExpiry = token.registrationExpiresAt {
                if let registrationExpiration = Self.parseISO8601Date(regExpiry) {
                    guard registrationExpiration > Date() else {
                        throw AWSSSOCredentialError.clientRegistrationExpired(profileName)
                    }
                }
            }

            logger.trace("SSO token expiring soon, refreshing via SSO-OIDC CreateToken")

            // Refresh token via SSO-OIDC CreateToken API
            let newToken = try await refreshAccessToken(
                refreshToken: refreshToken,
                clientId: clientId,
                clientSecret: clientSecret,
                region: config.ssoRegion,
                originalToken: token,
                logger: logger
            )

            // Save updated token to cache
            try await saveToken(newToken, to: tokenPath, fileIO: fileIO, threadPool: threadPool)

            token = newToken
        }

        return token
    }

    // MARK: - Token Refresh via SSO-OIDC CreateToken

    private func refreshAccessToken(
        refreshToken: String,
        clientId: String,
        clientSecret: String,
        region: Region,
        originalToken: SSOToken,
        logger: Logger
    ) async throws -> SSOToken {
        let endpoint = "oidc.\(region.rawValue).amazonaws.com"

        // Build JSON body per SSO-OIDC CreateToken API spec
        let requestBody: [String: String] = [
            "grantType": "refresh_token",
            "clientId": clientId,
            "clientSecret": clientSecret,
            "refreshToken": refreshToken,
        ]
        let bodyData = try JSONEncoder().encode(requestBody)

        // Create HTTP request
        var headers = HTTPHeaders()
        headers.add(name: "Content-Type", value: "application/json")
        headers.add(name: "Host", value: endpoint)
        headers.add(name: "Content-Length", value: "\(bodyData.count)")

        guard let url = URL(string: "https://\(endpoint)/token") else {
            throw AWSSSOCredentialError.tokenRefreshFailed("Failed to construct SSO-OIDC endpoint URL")
        }

        let request = AWSHTTPRequest(
            url: url,
            method: .POST,
            headers: headers,
            body: .init(bytes: bodyData)
        )

        // Execute request (no signing - uses OAUTH client credentials)
        let response = try await httpClient.execute(request: request, timeout: .seconds(30), logger: logger)

        guard (200...299).contains(response.status.code) else {
            throw AWSSSOCredentialError.tokenRefreshFailed(
                "Failed to refresh SSO token: HTTP \(response.status.code)"
            )
        }

        let body = try await response.body.collect(upTo: 1024 * 1024)
        let decoder = JSONDecoder()
        let tokenResponse = try decoder.decode(CreateTokenResponse.self, from: Data(buffer: body))

        // Calculate new expiration
        let newExpiration = Date(timeIntervalSinceNow: TimeInterval(tokenResponse.expiresIn))

        // Return updated token, preserving original fields where new values not provided
        return SSOToken(
            accessToken: tokenResponse.accessToken,
            expiresAt: ISO8601DateCoder.string(from: newExpiration) ?? "",
            refreshToken: tokenResponse.refreshToken ?? refreshToken,
            clientId: clientId,
            clientSecret: clientSecret,
            registrationExpiresAt: originalToken.registrationExpiresAt,
            startUrl: originalToken.startUrl,
            region: originalToken.region
        )
    }

    // MARK: - Date Parsing

    /// Parse an ISO8601 date string, handling both with and without fractional seconds.
    /// AWS CLI writes dates with fractional seconds (e.g., "2026-02-18T16:59:23.216Z").
    static func parseISO8601Date(_ string: String) -> Date? {
        #if canImport(FoundationEssentials)
        if let date = try? Date(string, strategy: Date.ISO8601FormatStyle(includingFractionalSeconds: true)) {
            return date
        }
        return try? Date(string, strategy: .iso8601)
        #else
        if #available(iOS 15, macOS 12, tvOS 15, watchOS 8, *) {
            if let date = try? Date(string, strategy: Date.ISO8601FormatStyle(includingFractionalSeconds: true)) {
                return date
            }
            return try? Date(string, strategy: .iso8601)
        } else {
            return ISO8601DateCoder.dateFormatters.lazy.compactMap { $0.date(from: string) }.first
        }
        #endif
    }
}
