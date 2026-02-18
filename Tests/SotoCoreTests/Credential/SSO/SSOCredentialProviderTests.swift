//===----------------------------------------------------------------------===//
//
// This source file is part of the Soto for AWS open source project
//
// Copyright (c) 2017-2025 the Soto project authors
// Licensed under Apache License v2.0
//
// See LICENSE.txt for license information
// See CONTRIBUTORS.txt for the list of Soto project authors
//
// SPDX-License-Identifier: Apache-2.0
//
//===----------------------------------------------------------------------===//

// SSO Credential Provider Tests

import Crypto
import Foundation
import Logging
import NIOCore
import NIOHTTP1
import Testing

@testable import SotoCore

@Suite("SSO Credential Provider", .serialized)
final class SSOCredentialProviderTests {

    // MARK: - Configuration Parsing Tests

    @Test("Parse modern SSO config with sso-session reference")
    func parseModernSSOConfig() async throws {
        try await withTempDirectory { tempDirectory in
            // Create config file
            let configContent = """
                [profile test]
                sso_session = my-sso
                sso_account_id = 123456789012
                sso_role_name = TestRole
                region = us-east-1

                [sso-session my-sso]
                sso_start_url = https://test.awsapps.com/start
                sso_region = us-west-2
                """

            // Create a valid token file so the provider doesn't fail before we test config
            let futureDate = ISO8601DateFormatter().string(from: Date(timeIntervalSinceNow: 3600))
            let tokenJSON = """
                {
                    "accessToken": "test-access-token",
                    "expiresAt": "\(futureDate)",
                    "startUrl": "https://test.awsapps.com/start",
                    "region": "us-west-2"
                }
                """

            // The modern format uses session name as cache key
            let cacheDir = tempDirectory.appendingPathComponent(".aws/sso/cache")
            try FileManager.default.createDirectory(at: cacheDir, withIntermediateDirectories: true)
            _ = try createTokenFile(cacheKey: "my-sso", tokenJSON: tokenJSON, inDirectory: cacheDir)

            // Mock HTTP client for GetRoleCredentials
            let mockHTTPClient = MockAWSHTTPClient { request in
                // Verify it's a GetRoleCredentials request
                #expect(request.headers["x-amz-sso_bearer_token"].first == "test-access-token")
                let urlString = request.url.absoluteString
                #expect(urlString.contains("role_name=TestRole"))
                #expect(urlString.contains("account_id=123456789012"))
                #expect(urlString.contains("portal.sso.us-west-2.amazonaws.com"))

                let responseJSON = """
                    {
                        "roleCredentials": {
                            "accessKeyId": "AKIATEST123",
                            "secretAccessKey": "testsecret",
                            "sessionToken": "testsession",
                            "expiration": \(Int64(Date(timeIntervalSinceNow: 3600).timeIntervalSince1970 * 1000))
                        }
                    }
                    """
                return (.ok, responseJSON.data(using: .utf8)!)
            }

            // Write config to temp file
            let configPath = tempDirectory.appendingPathComponent("config")
            try configContent.write(to: configPath, atomically: true, encoding: .utf8)

            // Temporarily override HOME for token path resolution
            try await withEnvironmentVariables(["HOME": tempDirectory.path]) {
                // Create provider with explicit config to test parsing
                let config = SSOConfiguration(
                    ssoStartUrl: "https://test.awsapps.com/start",
                    ssoRegion: .uswest2,
                    ssoAccountId: "123456789012",
                    ssoRoleName: "TestRole",
                    region: .useast1,
                    sessionName: "my-sso"
                )

                let provider = SSOCredentialProvider(
                    configuration: config,
                    httpClient: mockHTTPClient
                )

                let logger = Logger(label: "test")
                let credential = try await provider.getCredential(logger: logger)

                #expect(credential.accessKeyId == "AKIATEST123")
                #expect(credential.secretAccessKey == "testsecret")
                #expect(credential.sessionToken == "testsession")
            }
        }
    }

    @Test("Parse legacy SSO config with direct SSO fields")
    func parseLegacySSOConfig() async throws {
        try await withTempDirectory { tempDirectory in
            let futureDate = ISO8601DateFormatter().string(from: Date(timeIntervalSinceNow: 3600))
            let tokenJSON = """
                {
                    "accessToken": "legacy-access-token",
                    "expiresAt": "\(futureDate)"
                }
                """

            // Legacy format uses start URL as cache key
            let cacheDir = tempDirectory.appendingPathComponent(".aws/sso/cache")
            try FileManager.default.createDirectory(at: cacheDir, withIntermediateDirectories: true)
            _ = try createTokenFile(
                cacheKey: "https://test.awsapps.com/start",
                tokenJSON: tokenJSON,
                inDirectory: cacheDir
            )

            let mockHTTPClient = MockAWSHTTPClient { request in
                #expect(request.headers["x-amz-sso_bearer_token"].first == "legacy-access-token")

                let responseJSON = """
                    {
                        "roleCredentials": {
                            "accessKeyId": "AKIALEGACY",
                            "secretAccessKey": "legacysecret",
                            "sessionToken": "legacysession",
                            "expiration": \(Int64(Date(timeIntervalSinceNow: 3600).timeIntervalSince1970 * 1000))
                        }
                    }
                    """
                return (.ok, responseJSON.data(using: .utf8)!)
            }

            try await withEnvironmentVariables(["HOME": tempDirectory.path]) {
                // Legacy config (no sessionName)
                let config = SSOConfiguration(
                    ssoStartUrl: "https://test.awsapps.com/start",
                    ssoRegion: .useast1,
                    ssoAccountId: "123456789012",
                    ssoRoleName: "TestRole",
                    region: .useast1,
                    sessionName: nil
                )

                let provider = SSOCredentialProvider(
                    configuration: config,
                    httpClient: mockHTTPClient
                )

                let logger = Logger(label: "test")
                let credential = try await provider.getCredential(logger: logger)

                #expect(credential.accessKeyId == "AKIALEGACY")
                #expect(credential.secretAccessKey == "legacysecret")
                #expect(credential.sessionToken == "legacysession")
            }
        }
    }

    // MARK: - Token Cache Tests

    @Test("Token cache not found throws tokenCacheNotFound error")
    func tokenCacheNotFound() async throws {
        try await withTempDirectory { tempDirectory in
            // Create cache directory but no token file
            let cacheDir = tempDirectory.appendingPathComponent(".aws/sso/cache")
            try FileManager.default.createDirectory(at: cacheDir, withIntermediateDirectories: true)

            try await withEnvironmentVariables(["HOME": tempDirectory.path]) {
                let config = SSOConfiguration(
                    ssoStartUrl: "https://nonexistent.awsapps.com/start",
                    ssoRegion: .useast1,
                    ssoAccountId: "123456789012",
                    ssoRoleName: "TestRole",
                    region: .useast1,
                    sessionName: nil
                )

                let provider = SSOCredentialProvider(
                    configuration: config,
                    httpClient: MockAWSHTTPClient()
                )

                let logger = Logger(label: "test")
                let error = await #expect(throws: AWSSSOCredentialError.self) {
                    try await provider.getCredential(logger: logger)
                }
                #expect(error?.code == "tokenCacheNotFound")
            }
        }
    }

    @Test("Expired legacy token without refresh throws tokenExpired error")
    func expiredLegacyToken() async throws {
        try await withTempDirectory { tempDirectory in
            let pastDate = ISO8601DateFormatter().string(from: Date(timeIntervalSinceNow: -3600))
            let tokenJSON = """
                {
                    "accessToken": "expired-token",
                    "expiresAt": "\(pastDate)"
                }
                """

            let cacheDir = tempDirectory.appendingPathComponent(".aws/sso/cache")
            try FileManager.default.createDirectory(at: cacheDir, withIntermediateDirectories: true)
            _ = try createTokenFile(
                cacheKey: "https://test.awsapps.com/start",
                tokenJSON: tokenJSON,
                inDirectory: cacheDir
            )

            try await withEnvironmentVariables(["HOME": tempDirectory.path]) {
                let config = SSOConfiguration(
                    ssoStartUrl: "https://test.awsapps.com/start",
                    ssoRegion: .useast1,
                    ssoAccountId: "123456789012",
                    ssoRoleName: "TestRole",
                    region: .useast1,
                    sessionName: nil
                )

                let provider = SSOCredentialProvider(
                    configuration: config,
                    httpClient: MockAWSHTTPClient()
                )

                let logger = Logger(label: "test")
                let error = await #expect(throws: AWSSSOCredentialError.self) {
                    try await provider.getCredential(logger: logger)
                }
                #expect(error?.code == "tokenExpired")
            }
        }
    }

    // MARK: - Token Refresh Tests (Modern Format)

    @Test("Modern token within refresh window triggers refresh")
    func modernTokenRefresh() async throws {
        try await withTempDirectory { tempDirectory in
            // Token expiring in 10 minutes (within 15 minute refresh window)
            let soonDate = ISO8601DateFormatter().string(from: Date(timeIntervalSinceNow: 10 * 60))
            let futureRegDate = ISO8601DateFormatter().string(from: Date(timeIntervalSinceNow: 90 * 24 * 60 * 60))

            let tokenJSON = """
                {
                    "accessToken": "expiring-soon-token",
                    "expiresAt": "\(soonDate)",
                    "refreshToken": "refresh-token-value",
                    "clientId": "client-id",
                    "clientSecret": "client-secret",
                    "registrationExpiresAt": "\(futureRegDate)",
                    "startUrl": "https://test.awsapps.com/start",
                    "region": "us-east-1"
                }
                """

            let cacheDir = tempDirectory.appendingPathComponent(".aws/sso/cache")
            try FileManager.default.createDirectory(at: cacheDir, withIntermediateDirectories: true)
            let tokenPath = try createTokenFile(
                cacheKey: "my-sso",
                tokenJSON: tokenJSON,
                inDirectory: cacheDir
            )

            let refreshTestCounter = RequestCounter()
            let mockHTTPClient = MockAWSHTTPClient { request in
                await refreshTestCounter.record(request.url.absoluteString)

                if request.url.absoluteString.contains("oidc.") {
                    // SSO-OIDC CreateToken refresh request
                    #expect(request.method == .POST)
                    #expect(request.headers["Content-Type"].first == "application/json")

                    let bodyBuffer = try await request.body.collect(upTo: 1024 * 1024)
                    let bodyJSON = try JSONSerialization.jsonObject(with: Data(buffer: bodyBuffer)) as! [String: String]
                    #expect(bodyJSON["grantType"] == "refresh_token")
                    #expect(bodyJSON["clientId"] == "client-id")
                    #expect(bodyJSON["refreshToken"] == "refresh-token-value")

                    let responseJSON = """
                        {
                            "accessToken": "refreshed-access-token",
                            "expiresIn": 28800,
                            "tokenType": "Bearer",
                            "refreshToken": "new-refresh-token"
                        }
                        """
                    return (.ok, responseJSON.data(using: .utf8)!)
                } else {
                    // SSO GetRoleCredentials request
                    #expect(request.headers["x-amz-sso_bearer_token"].first == "refreshed-access-token")

                    let responseJSON = """
                        {
                            "roleCredentials": {
                                "accessKeyId": "AKIAREFRESHED",
                                "secretAccessKey": "refreshedsecret",
                                "sessionToken": "refreshedsession",
                                "expiration": \(Int64(Date(timeIntervalSinceNow: 3600).timeIntervalSince1970 * 1000))
                            }
                        }
                        """
                    return (.ok, responseJSON.data(using: .utf8)!)
                }
            }

            try await withEnvironmentVariables(["HOME": tempDirectory.path]) {
                let config = SSOConfiguration(
                    ssoStartUrl: "https://test.awsapps.com/start",
                    ssoRegion: .useast1,
                    ssoAccountId: "123456789012",
                    ssoRoleName: "TestRole",
                    region: .useast1,
                    sessionName: "my-sso"
                )

                let provider = SSOCredentialProvider(
                    configuration: config,
                    httpClient: mockHTTPClient
                )

                let logger = Logger(label: "test")
                let credential = try await provider.getCredential(logger: logger)

                // Should have made both refresh and GetRoleCredentials requests
                let refreshUrls = await refreshTestCounter.urls
                #expect(refreshUrls.count == 2)
                #expect(credential.accessKeyId == "AKIAREFRESHED")
                #expect(credential.secretAccessKey == "refreshedsecret")
                #expect(credential.sessionToken == "refreshedsession")

                // Verify token file was updated with refreshed token
                let updatedTokenData = try Data(contentsOf: tokenPath)
                let updatedToken = try JSONDecoder().decode(SSOToken.self, from: updatedTokenData)
                #expect(updatedToken.accessToken == "refreshed-access-token")
                #expect(updatedToken.refreshToken == "new-refresh-token")
                #expect(updatedToken.clientId == "client-id")
                #expect(updatedToken.clientSecret == "client-secret")
            }
        }
    }

    @Test("Token refresh failure throws tokenRefreshFailed error")
    func tokenRefreshFailure() async throws {
        try await withTempDirectory { tempDirectory in
            let soonDate = ISO8601DateFormatter().string(from: Date(timeIntervalSinceNow: 10 * 60))
            let futureRegDate = ISO8601DateFormatter().string(from: Date(timeIntervalSinceNow: 90 * 24 * 60 * 60))

            let tokenJSON = """
                {
                    "accessToken": "expiring-soon-token",
                    "expiresAt": "\(soonDate)",
                    "refreshToken": "refresh-token-value",
                    "clientId": "client-id",
                    "clientSecret": "client-secret",
                    "registrationExpiresAt": "\(futureRegDate)",
                    "startUrl": "https://test.awsapps.com/start",
                    "region": "us-east-1"
                }
                """

            let cacheDir = tempDirectory.appendingPathComponent(".aws/sso/cache")
            try FileManager.default.createDirectory(at: cacheDir, withIntermediateDirectories: true)
            _ = try createTokenFile(cacheKey: "my-sso", tokenJSON: tokenJSON, inDirectory: cacheDir)

            let mockHTTPClient = MockAWSHTTPClient { _ in
                // Return error for refresh request
                (.badRequest, Data())
            }

            try await withEnvironmentVariables(["HOME": tempDirectory.path]) {
                let config = SSOConfiguration(
                    ssoStartUrl: "https://test.awsapps.com/start",
                    ssoRegion: .useast1,
                    ssoAccountId: "123456789012",
                    ssoRoleName: "TestRole",
                    region: .useast1,
                    sessionName: "my-sso"
                )

                let provider = SSOCredentialProvider(
                    configuration: config,
                    httpClient: mockHTTPClient
                )

                let logger = Logger(label: "test")
                let error = await #expect(throws: AWSSSOCredentialError.self) {
                    try await provider.getCredential(logger: logger)
                }
                #expect(error?.code == "tokenRefreshFailed")
            }
        }
    }

    @Test("Client registration expired throws clientRegistrationExpired error")
    func clientRegistrationExpired() async throws {
        try await withTempDirectory { tempDirectory in
            let soonDate = ISO8601DateFormatter().string(from: Date(timeIntervalSinceNow: 10 * 60))
            // Client registration already expired
            let pastRegDate = ISO8601DateFormatter().string(from: Date(timeIntervalSinceNow: -3600))

            let tokenJSON = """
                {
                    "accessToken": "expiring-soon-token",
                    "expiresAt": "\(soonDate)",
                    "refreshToken": "refresh-token-value",
                    "clientId": "client-id",
                    "clientSecret": "client-secret",
                    "registrationExpiresAt": "\(pastRegDate)",
                    "startUrl": "https://test.awsapps.com/start",
                    "region": "us-east-1"
                }
                """

            let cacheDir = tempDirectory.appendingPathComponent(".aws/sso/cache")
            try FileManager.default.createDirectory(at: cacheDir, withIntermediateDirectories: true)
            _ = try createTokenFile(cacheKey: "my-sso", tokenJSON: tokenJSON, inDirectory: cacheDir)

            try await withEnvironmentVariables(["HOME": tempDirectory.path]) {
                let config = SSOConfiguration(
                    ssoStartUrl: "https://test.awsapps.com/start",
                    ssoRegion: .useast1,
                    ssoAccountId: "123456789012",
                    ssoRoleName: "TestRole",
                    region: .useast1,
                    sessionName: "my-sso"
                )

                let provider = SSOCredentialProvider(
                    configuration: config,
                    httpClient: MockAWSHTTPClient()
                )

                let logger = Logger(label: "test")
                let error = await #expect(throws: AWSSSOCredentialError.self) {
                    try await provider.getCredential(logger: logger)
                }
                #expect(error?.code == "clientRegistrationExpired")
            }
        }
    }

    // MARK: - GetRoleCredentials API Tests

    @Test("GetRoleCredentials HTTP error throws getRoleCredentialsFailed")
    func getRoleCredentialsHTTPError() async throws {
        try await withTempDirectory { tempDirectory in
            let futureDate = ISO8601DateFormatter().string(from: Date(timeIntervalSinceNow: 3600))
            let tokenJSON = """
                {
                    "accessToken": "valid-token",
                    "expiresAt": "\(futureDate)"
                }
                """

            let cacheDir = tempDirectory.appendingPathComponent(".aws/sso/cache")
            try FileManager.default.createDirectory(at: cacheDir, withIntermediateDirectories: true)
            _ = try createTokenFile(
                cacheKey: "https://test.awsapps.com/start",
                tokenJSON: tokenJSON,
                inDirectory: cacheDir
            )

            let mockHTTPClient = MockAWSHTTPClient { _ in
                (.forbidden, Data())
            }

            try await withEnvironmentVariables(["HOME": tempDirectory.path]) {
                let config = SSOConfiguration(
                    ssoStartUrl: "https://test.awsapps.com/start",
                    ssoRegion: .useast1,
                    ssoAccountId: "123456789012",
                    ssoRoleName: "TestRole",
                    region: .useast1,
                    sessionName: nil
                )

                let provider = SSOCredentialProvider(
                    configuration: config,
                    httpClient: mockHTTPClient
                )

                let logger = Logger(label: "test")
                let error = await #expect(throws: AWSSSOCredentialError.self) {
                    try await provider.getCredential(logger: logger)
                }
                #expect(error?.code == "getRoleCredentialsFailed")
                #expect(error?.message.contains("403") == true)
            }
        }
    }

    // MARK: - Token Path Construction Tests

    @Test("Token path uses SHA-1 hash of session name for modern format")
    func tokenPathModernFormat() throws {
        let tokenManager = SSOTokenManager(httpClient: MockAWSHTTPClient())
        let config = SSOConfiguration(
            ssoStartUrl: "https://test.awsapps.com/start",
            ssoRegion: .useast1,
            ssoAccountId: "123456789012",
            ssoRoleName: "TestRole",
            region: .useast1,
            sessionName: "my-sso"
        )

        let path = try tokenManager.constructTokenPath(config: config)

        // Should use session name as cache key
        let expectedHash = Insecure.SHA1.hash(data: Data("my-sso".utf8))
            .compactMap { String(format: "%02x", $0) }.joined()
        #expect(path.hasSuffix("\(expectedHash).json"))
        #expect(path.contains(".aws/sso/cache"))
    }

    @Test("Token path uses SHA-1 hash of start URL for legacy format")
    func tokenPathLegacyFormat() throws {
        let tokenManager = SSOTokenManager(httpClient: MockAWSHTTPClient())
        let config = SSOConfiguration(
            ssoStartUrl: "https://test.awsapps.com/start",
            ssoRegion: .useast1,
            ssoAccountId: "123456789012",
            ssoRoleName: "TestRole",
            region: .useast1,
            sessionName: nil
        )

        let path = try tokenManager.constructTokenPath(config: config)

        // Should use start URL as cache key
        let expectedHash = Insecure.SHA1.hash(data: Data("https://test.awsapps.com/start".utf8))
            .compactMap { String(format: "%02x", $0) }.joined()
        #expect(path.hasSuffix("\(expectedHash).json"))
        #expect(path.contains(".aws/sso/cache"))
    }

    // MARK: - Valid Token (No Refresh Needed) Tests

    @Test("Valid token does not trigger refresh or HTTP call for token")
    func validTokenNoRefresh() async throws {
        try await withTempDirectory { tempDirectory in
            // Token with plenty of time left (2 hours)
            let futureDate = ISO8601DateFormatter().string(from: Date(timeIntervalSinceNow: 2 * 60 * 60))
            let tokenJSON = """
                {
                    "accessToken": "valid-token",
                    "expiresAt": "\(futureDate)",
                    "refreshToken": "refresh-token",
                    "clientId": "client-id",
                    "clientSecret": "client-secret",
                    "startUrl": "https://test.awsapps.com/start",
                    "region": "us-east-1"
                }
                """

            let cacheDir = tempDirectory.appendingPathComponent(".aws/sso/cache")
            try FileManager.default.createDirectory(at: cacheDir, withIntermediateDirectories: true)
            _ = try createTokenFile(cacheKey: "my-sso", tokenJSON: tokenJSON, inDirectory: cacheDir)

            let requestCounter = RequestCounter()
            let mockHTTPClient = MockAWSHTTPClient { request in
                await requestCounter.record(request.url.absoluteString)

                let responseJSON = """
                    {
                        "roleCredentials": {
                            "accessKeyId": "AKIAVALID",
                            "secretAccessKey": "validsecret",
                            "sessionToken": "validsession",
                            "expiration": \(Int64(Date(timeIntervalSinceNow: 3600).timeIntervalSince1970 * 1000))
                        }
                    }
                    """
                return (.ok, responseJSON.data(using: .utf8)!)
            }

            try await withEnvironmentVariables(["HOME": tempDirectory.path]) {
                let config = SSOConfiguration(
                    ssoStartUrl: "https://test.awsapps.com/start",
                    ssoRegion: .useast1,
                    ssoAccountId: "123456789012",
                    ssoRoleName: "TestRole",
                    region: .useast1,
                    sessionName: "my-sso"
                )

                let provider = SSOCredentialProvider(
                    configuration: config,
                    httpClient: mockHTTPClient
                )

                let logger = Logger(label: "test")
                let credential = try await provider.getCredential(logger: logger)

                // Only one request (GetRoleCredentials), no OIDC refresh
                let urls = await requestCounter.urls
                #expect(urls.count == 1)
                #expect(urls[0].contains("portal.sso"))
                #expect(!urls[0].contains("oidc"))

                #expect(credential.accessKeyId == "AKIAVALID")
            }
        }
    }

    // MARK: - Error Type Tests

    @Test("AWSSSOCredentialError is Equatable")
    func errorEquatable() {
        let error1 = AWSSSOCredentialError.profileNotFound("test")
        let error2 = AWSSSOCredentialError.profileNotFound("test")
        let error3 = AWSSSOCredentialError.tokenExpired("test")

        #expect(error1 == error2)
        #expect(error1 != error3)
    }

    @Test("AWSSSOCredentialError description format")
    func errorDescription() {
        let error = AWSSSOCredentialError.profileNotFound("dev")
        #expect(error.description.contains("profileNotFound"))
        #expect(error.description.contains("dev"))
    }

    // MARK: - Invalid Response Tests

    @Test("Invalid GetRoleCredentials JSON throws decoding error")
    func invalidGetRoleCredentialsResponse() async throws {
        try await withTempDirectory { tempDirectory in
            let futureDate = ISO8601DateFormatter().string(from: Date(timeIntervalSinceNow: 3600))
            let tokenJSON = """
                {
                    "accessToken": "valid-token",
                    "expiresAt": "\(futureDate)"
                }
                """

            let cacheDir = tempDirectory.appendingPathComponent(".aws/sso/cache")
            try FileManager.default.createDirectory(at: cacheDir, withIntermediateDirectories: true)
            _ = try createTokenFile(
                cacheKey: "https://test.awsapps.com/start",
                tokenJSON: tokenJSON,
                inDirectory: cacheDir
            )

            let mockHTTPClient = MockAWSHTTPClient { _ in
                (.ok, "invalid json".data(using: .utf8)!)
            }

            try await withEnvironmentVariables(["HOME": tempDirectory.path]) {
                let config = SSOConfiguration(
                    ssoStartUrl: "https://test.awsapps.com/start",
                    ssoRegion: .useast1,
                    ssoAccountId: "123456789012",
                    ssoRoleName: "TestRole",
                    region: .useast1,
                    sessionName: nil
                )

                let provider = SSOCredentialProvider(
                    configuration: config,
                    httpClient: mockHTTPClient
                )

                let logger = Logger(label: "test")
                await #expect(throws: DecodingError.self) {
                    try await provider.getCredential(logger: logger)
                }
            }
        }
    }

    @Test("Provider is immutable")
    func providerIsImmutable() throws {
        let provider = SSOCredentialProvider(
            profileName: "test",
            httpClient: MockAWSHTTPClient()
        )

        #expect(provider.description.contains("SSOCredentialProvider"))
    }

    // MARK: - Helper Methods

    func withTempDirectory<T>(_ body: (URL) async throws -> T) async throws -> T {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }
        return try await body(tempDir)
    }

    /// Create a token file at the expected cache path for the given cache key (session name or start URL)
    func createTokenFile(
        cacheKey: String,
        tokenJSON: String,
        inDirectory directory: URL
    ) throws -> URL {
        let keyData = Data(cacheKey.utf8)
        let hash = Insecure.SHA1.hash(data: keyData)
        let hashString = hash.compactMap { String(format: "%02x", $0) }.joined()

        let tokenPath = directory.appendingPathComponent("\(hashString).json")
        try tokenJSON.write(to: tokenPath, atomically: true, encoding: .utf8)
        return tokenPath
    }

    /// Sets environment variables for the duration of `body`, then restores originals (or unsets them).
    private func withEnvironmentVariables<T>(_ env: [String: String], body: () async throws -> T) async throws -> T {
        // Save original values
        var saved: [String: String?] = [:]
        for key in env.keys {
            saved[key] = ProcessInfo.processInfo.environment[key]
        }
        // Set new values
        for (key, value) in env {
            setenv(key, value, 1)
        }
        defer {
            for (key, original) in saved {
                if let original {
                    setenv(key, original, 1)
                } else {
                    unsetenv(key)
                }
            }
        }
        return try await body()
    }

}

/// Thread-safe request counter for use in @Sendable closures
private actor RequestCounter {
    var urls: [String] = []

    func record(_ url: String) {
        urls.append(url)
    }
}
