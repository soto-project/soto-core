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
//
// Note: The ideal pattern for error assertions in Swift Testing is:
//   let error = await #expect(throws: AWSSSOCredentialError.self) { ... }
//   #expect(error?.code == "expectedCode")
// However, the return-value variant of #expect(throws:) was introduced in Swift 6.1.
// On Swift 6.0 it returns Void, so we use the closure-based validation pattern instead:
//   await #expect { ... } throws: { error in (error as? AWSSSOCredentialError)?.code == "expectedCode" }

import Crypto
import Foundation
import Logging
import NIOCore
import NIOHTTP1
import Testing

@testable import SotoCore

@Suite("SSO Credential Provider", .serialized)
final class SSOCredentialProviderTests {

    let logger = Logger(label: "test")

    // MARK: - Configuration Parsing Tests

    @Test("Parse modern SSO config with sso-session reference")
    func parseModernSSOConfig() async throws {
        try await withSSOEnvironment(cacheKey: "my-sso") { env in
            let mockHTTPClient = MockAWSHTTPClient { request in
                #expect(request.headers["x-amz-sso_bearer_token"].first == "test-access-token")
                let urlString = request.url.absoluteString
                #expect(urlString.contains("role_name=TestRole"))
                #expect(urlString.contains("account_id=123456789012"))
                #expect(urlString.contains("portal.sso.us-west-2.amazonaws.com"))
                return Self.makeRoleCredentialsResponse()
            }

            let config = SSOConfiguration(
                ssoStartUrl: "https://test.awsapps.com/start",
                ssoRegion: .uswest2,
                ssoAccountId: "123456789012",
                ssoRoleName: "TestRole",
                region: .useast1,
                sessionName: "my-sso"
            )

            let provider = SSOCredentialProvider(configuration: config, httpClient: mockHTTPClient)
            let credential = try await provider.getCredential(logger: logger)

            #expect(credential.accessKeyId == "AKIATEST123")
            #expect(credential.secretAccessKey == "testsecret")
            #expect(credential.sessionToken == "testsession")
        }
    }

    @Test("Parse legacy SSO config with direct SSO fields")
    func parseLegacySSOConfig() async throws {
        let startUrl = "https://test.awsapps.com/start"
        try await withSSOEnvironment(cacheKey: startUrl, accessToken: "legacy-access-token") { env in
            let mockHTTPClient = MockAWSHTTPClient { request in
                #expect(request.headers["x-amz-sso_bearer_token"].first == "legacy-access-token")
                return Self.makeRoleCredentialsResponse(accessKeyId: "AKIALEGACY", secretAccessKey: "legacysecret", sessionToken: "legacysession")
            }

            let provider = SSOCredentialProvider(configuration: self.makeLegacyConfig(), httpClient: mockHTTPClient)
            let credential = try await provider.getCredential(logger: logger)

            #expect(credential.accessKeyId == "AKIALEGACY")
            #expect(credential.secretAccessKey == "legacysecret")
            #expect(credential.sessionToken == "legacysession")
        }
    }

    // MARK: - Config File Parsing Tests

    @Test("Load modern SSO config from config file")
    func loadModernConfigFromFile() async throws {
        let configContent = """
            [profile dev]
            sso_session = my-sso
            sso_account_id = 111122223333
            sso_role_name = DevRole
            region = eu-west-1

            [sso-session my-sso]
            sso_start_url = https://myorg.awsapps.com/start
            sso_region = us-west-2
            """

        try await withSSOEnvironment(cacheKey: "my-sso", accessToken: "config-test-token", configContent: configContent) { env in
            let mockHTTPClient = MockAWSHTTPClient { request in
                let urlString = request.url.absoluteString
                #expect(urlString.contains("portal.sso.us-west-2.amazonaws.com"))
                #expect(urlString.contains("role_name=DevRole"))
                #expect(urlString.contains("account_id=111122223333"))
                #expect(request.headers["x-amz-sso_bearer_token"].first == "config-test-token")
                return Self.makeRoleCredentialsResponse(accessKeyId: "AKIACONFIG")
            }

            let provider = SSOCredentialProvider(profileName: "dev", configPath: env.configPath!, httpClient: mockHTTPClient)
            let credential = try await provider.getCredential(logger: logger)
            #expect(credential.accessKeyId == "AKIACONFIG")
        }
    }

    @Test("Load legacy SSO config from config file")
    func loadLegacyConfigFromFile() async throws {
        let configContent = """
            [profile legacy]
            sso_start_url = https://legacy.awsapps.com/start
            sso_region = eu-central-1
            sso_account_id = 444455556666
            sso_role_name = LegacyRole
            region = eu-central-1
            """

        try await withSSOEnvironment(
            cacheKey: "https://legacy.awsapps.com/start",
            configContent: configContent
        ) { env in
            let mockHTTPClient = MockAWSHTTPClient { request in
                let urlString = request.url.absoluteString
                #expect(urlString.contains("portal.sso.eu-central-1.amazonaws.com"))
                #expect(urlString.contains("role_name=LegacyRole"))
                #expect(urlString.contains("account_id=444455556666"))
                return Self.makeRoleCredentialsResponse(accessKeyId: "AKIALEGACYCFG")
            }

            let provider = SSOCredentialProvider(profileName: "legacy", configPath: env.configPath!, httpClient: mockHTTPClient)
            let credential = try await provider.getCredential(logger: logger)
            #expect(credential.accessKeyId == "AKIALEGACYCFG")
        }
    }

    @Test("Default profile uses 'default' key without 'profile' prefix")
    func defaultProfileConfig() async throws {
        let configContent = """
            [default]
            sso_start_url = https://default.awsapps.com/start
            sso_region = us-east-1
            sso_account_id = 777788889999
            sso_role_name = DefaultRole
            """

        try await withSSOEnvironment(
            cacheKey: "https://default.awsapps.com/start",
            configContent: configContent
        ) { env in
            let mockHTTPClient = MockAWSHTTPClient { request in
                #expect(request.url.absoluteString.contains("role_name=DefaultRole"))
                return Self.makeRoleCredentialsResponse(accessKeyId: "AKIADEFAULT")
            }

            // No profileName = defaults to "default"
            let provider = SSOCredentialProvider(configPath: env.configPath!, httpClient: mockHTTPClient)
            let credential = try await provider.getCredential(logger: logger)
            #expect(credential.accessKeyId == "AKIADEFAULT")
        }
    }

    @Test("Config file not found throws configFileNotFound error")
    func configFileNotFound() async throws {
        try await withTempDirectory { tempDirectory in
            let provider = SSOCredentialProvider(
                profileName: "test",
                configPath: tempDirectory.appendingPathComponent("nonexistent").path,
                httpClient: MockAWSHTTPClient()
            )

            await #expect {
                try await provider.getCredential(logger: self.logger)
            } throws: { error in
                (error as? AWSSSOCredentialError)?.code == "configFileNotFound"
            }
        }
    }

    @Test("Profile not found throws profileNotFound error")
    func profileNotFound() async throws {
        try await withConfigFile("""
            [profile existing]
            sso_start_url = https://test.awsapps.com/start
            sso_region = us-east-1
            sso_account_id = 123456789012
            sso_role_name = TestRole
            """) { configPath in
            let provider = SSOCredentialProvider(profileName: "nonexistent", configPath: configPath, httpClient: MockAWSHTTPClient())

            await #expect {
                try await provider.getCredential(logger: self.logger)
            } throws: { error in
                (error as? AWSSSOCredentialError)?.code == "profileNotFound"
            }
        }
    }

    @Test("Missing sso-session section throws ssoSessionNotFound error")
    func ssoSessionNotFound() async throws {
        try await withConfigFile("""
            [profile broken]
            sso_session = nonexistent-session
            sso_account_id = 123456789012
            sso_role_name = TestRole
            """) { configPath in
            let provider = SSOCredentialProvider(profileName: "broken", configPath: configPath, httpClient: MockAWSHTTPClient())

            await #expect {
                try await provider.getCredential(logger: self.logger)
            } throws: { error in
                (error as? AWSSSOCredentialError)?.code == "ssoSessionNotFound"
            }
        }
    }

    @Test("Missing required SSO fields throws ssoConfigMissing error")
    func ssoConfigMissingFields() async throws {
        // Session section missing sso_start_url
        try await withConfigFile("""
            [profile incomplete]
            sso_session = my-sso
            sso_account_id = 123456789012
            sso_role_name = TestRole

            [sso-session my-sso]
            sso_region = us-east-1
            """) { configPath in
            let provider = SSOCredentialProvider(profileName: "incomplete", configPath: configPath, httpClient: MockAWSHTTPClient())

            await #expect {
                try await provider.getCredential(logger: self.logger)
            } throws: { error in
                (error as? AWSSSOCredentialError)?.code == "ssoConfigMissing"
            }
        }
    }

    @Test("Legacy profile missing required fields throws ssoConfigMissing error")
    func legacyConfigMissingFields() async throws {
        // Legacy profile missing sso_role_name
        try await withConfigFile("""
            [profile partial]
            sso_start_url = https://test.awsapps.com/start
            sso_region = us-east-1
            sso_account_id = 123456789012
            """) { configPath in
            let provider = SSOCredentialProvider(profileName: "partial", configPath: configPath, httpClient: MockAWSHTTPClient())

            await #expect {
                try await provider.getCredential(logger: self.logger)
            } throws: { error in
                (error as? AWSSSOCredentialError)?.code == "ssoConfigMissing"
            }
        }
    }

    // MARK: - Token Cache Tests

    @Test("Invalid token JSON throws invalidTokenFormat error")
    func invalidTokenJSON() async throws {
        try await withSSOEnvironment(cacheKey: "https://test.awsapps.com/start", rawTokenJSON: "{ not valid json") { env in
            let provider = SSOCredentialProvider(configuration: self.makeLegacyConfig(), httpClient: MockAWSHTTPClient())

            await #expect {
                try await provider.getCredential(logger: self.logger)
            } throws: { error in
                (error as? AWSSSOCredentialError)?.code == "invalidTokenFormat"
            }
        }
    }

    @Test("Invalid expiresAt date format throws invalidTokenFormat error")
    func invalidExpiresAtFormat() async throws {
        let tokenJSON = """
            {
                "accessToken": "test-token",
                "expiresAt": "not-a-date"
            }
            """

        try await withSSOEnvironment(cacheKey: "https://test.awsapps.com/start", rawTokenJSON: tokenJSON) { env in
            let provider = SSOCredentialProvider(configuration: self.makeLegacyConfig(), httpClient: MockAWSHTTPClient())

            await #expect {
                try await provider.getCredential(logger: self.logger)
            } throws: { error in
                (error as? AWSSSOCredentialError)?.code == "invalidTokenFormat"
            }
        }
    }

    @Test("Token cache not found throws tokenCacheNotFound error")
    func tokenCacheNotFound() async throws {
        try await withTempDirectory { tempDirectory in
            // Create cache directory but no token file
            let cacheDir = tempDirectory.appendingPathComponent(".aws/sso/cache")
            try FileManager.default.createDirectory(at: cacheDir, withIntermediateDirectories: true)

            try await self.withEnvironmentVariables(["HOME": tempDirectory.path]) {
                let provider = SSOCredentialProvider(
                    configuration: self.makeLegacyConfig(startUrl: "https://nonexistent.awsapps.com/start"),
                    httpClient: MockAWSHTTPClient()
                )

                await #expect {
                    try await provider.getCredential(logger: self.logger)
                } throws: { error in
                    (error as? AWSSSOCredentialError)?.code == "tokenCacheNotFound"
                }
            }
        }
    }

    @Test("Expired legacy token without refresh throws tokenExpired error")
    func expiredLegacyToken() async throws {
        let startUrl = "https://test.awsapps.com/start"
        try await withSSOEnvironment(cacheKey: startUrl, expiresIn: -3600, accessToken: "expired-token") { env in
            let provider = SSOCredentialProvider(configuration: self.makeLegacyConfig(), httpClient: MockAWSHTTPClient())

            await #expect {
                try await provider.getCredential(logger: self.logger)
            } throws: { error in
                (error as? AWSSSOCredentialError)?.code == "tokenExpired"
            }
        }
    }

    // MARK: - Token Refresh Tests (Modern Format)

    @Test("Modern token within refresh window triggers refresh")
    func modernTokenRefresh() async throws {
        try await withSSOEnvironment(
            cacheKey: "my-sso",
            tokenJSON: makeModernTokenJSON(accessToken: "expiring-soon-token")
        ) { env in
            let requestCounter = RequestCounter()
            let mockHTTPClient = MockAWSHTTPClient { request in
                await requestCounter.record(request.url.absoluteString)

                if request.url.absoluteString.contains("oidc.") {
                    #expect(request.method == .POST)
                    #expect(request.headers["Content-Type"].first == "application/json")

                    let bodyBuffer = try await request.body.collect(upTo: 1024 * 1024)
                    let bodyJSON = try JSONSerialization.jsonObject(with: Data(buffer: bodyBuffer)) as! [String: String]
                    #expect(bodyJSON["grantType"] == "refresh_token")
                    #expect(bodyJSON["clientId"] == "client-id")
                    #expect(bodyJSON["refreshToken"] == "refresh-token-value")

                    return Self.makeCreateTokenResponse()
                } else {
                    #expect(request.headers["x-amz-sso_bearer_token"].first == "refreshed-access-token")
                    return Self.makeRoleCredentialsResponse(accessKeyId: "AKIAREFRESHED", secretAccessKey: "refreshedsecret", sessionToken: "refreshedsession")
                }
            }

            let provider = SSOCredentialProvider(configuration: self.makeModernConfig(), httpClient: mockHTTPClient)
            let credential = try await provider.getCredential(logger: self.logger)

            let refreshUrls = await requestCounter.urls
            #expect(refreshUrls.count == 2)
            #expect(credential.accessKeyId == "AKIAREFRESHED")
            #expect(credential.secretAccessKey == "refreshedsecret")
            #expect(credential.sessionToken == "refreshedsession")

            // Verify token file was updated
            let updatedTokenData = try Data(contentsOf: env.tokenPath!)
            let updatedToken = try JSONDecoder().decode(SSOToken.self, from: updatedTokenData)
            #expect(updatedToken.accessToken == "refreshed-access-token")
            #expect(updatedToken.refreshToken == "new-refresh-token")
            #expect(updatedToken.clientId == "client-id")
            #expect(updatedToken.clientSecret == "client-secret")
        }
    }

    @Test("Token refresh failure throws tokenRefreshFailed error")
    func tokenRefreshFailure() async throws {
        try await withSSOEnvironment(cacheKey: "my-sso", tokenJSON: makeModernTokenJSON()) { env in
            let mockHTTPClient = MockAWSHTTPClient { _ in (.badRequest, Data()) }
            let provider = SSOCredentialProvider(configuration: self.makeModernConfig(), httpClient: mockHTTPClient)

            await #expect {
                try await provider.getCredential(logger: self.logger)
            } throws: { error in
                (error as? AWSSSOCredentialError)?.code == "tokenRefreshFailed"
            }
        }
    }

    @Test("Client registration expired throws clientRegistrationExpired error")
    func clientRegistrationExpired() async throws {
        try await withSSOEnvironment(
            cacheKey: "my-sso",
            tokenJSON: makeModernTokenJSON(registrationExpiresIn: -3600)
        ) { env in
            let provider = SSOCredentialProvider(configuration: self.makeModernConfig(), httpClient: MockAWSHTTPClient())

            await #expect {
                try await provider.getCredential(logger: self.logger)
            } throws: { error in
                (error as? AWSSSOCredentialError)?.code == "clientRegistrationExpired"
            }
        }
    }

    // MARK: - GetRoleCredentials API Tests

    @Test("GetRoleCredentials HTTP error throws getRoleCredentialsFailed")
    func getRoleCredentialsHTTPError() async throws {
        let startUrl = "https://test.awsapps.com/start"
        try await withSSOEnvironment(cacheKey: startUrl) { env in
            let mockHTTPClient = MockAWSHTTPClient { _ in (.forbidden, Data()) }
            let provider = SSOCredentialProvider(configuration: self.makeLegacyConfig(), httpClient: mockHTTPClient)

            await #expect {
                try await provider.getCredential(logger: self.logger)
            } throws: { error in
                guard let error = error as? AWSSSOCredentialError else { return false }
                return error.code == "getRoleCredentialsFailed" && error.message.contains("403")
            }
        }
    }

    @Test("Invalid GetRoleCredentials JSON throws decoding error")
    func invalidGetRoleCredentialsResponse() async throws {
        let startUrl = "https://test.awsapps.com/start"
        try await withSSOEnvironment(cacheKey: startUrl) { env in
            let mockHTTPClient = MockAWSHTTPClient { _ in (.ok, "invalid json".data(using: .utf8)!) }
            let provider = SSOCredentialProvider(configuration: self.makeLegacyConfig(), httpClient: mockHTTPClient)

            await #expect(throws: DecodingError.self) {
                try await provider.getCredential(logger: self.logger)
            }
        }
    }

    // MARK: - Token Path Construction Tests

    @Test("Token path uses SHA-1 hash of session name for modern format")
    func tokenPathModernFormat() throws {
        let tokenManager = SSOTokenManager(httpClient: MockAWSHTTPClient())
        let path = try tokenManager.constructTokenPath(config: makeModernConfig())

        let expectedHash = Insecure.SHA1.hash(data: Data("my-sso".utf8))
            .compactMap { String(format: "%02x", $0) }.joined()
        #expect(path.hasSuffix("\(expectedHash).json"))
        #expect(path.contains(".aws/sso/cache"))
    }

    @Test("Token path uses SHA-1 hash of start URL for legacy format")
    func tokenPathLegacyFormat() throws {
        let tokenManager = SSOTokenManager(httpClient: MockAWSHTTPClient())
        let path = try tokenManager.constructTokenPath(config: makeLegacyConfig())

        let expectedHash = Insecure.SHA1.hash(data: Data("https://test.awsapps.com/start".utf8))
            .compactMap { String(format: "%02x", $0) }.joined()
        #expect(path.hasSuffix("\(expectedHash).json"))
        #expect(path.contains(".aws/sso/cache"))
    }

    // MARK: - Valid Token (No Refresh Needed) Tests

    @Test("Valid token does not trigger refresh or HTTP call for token")
    func validTokenNoRefresh() async throws {
        try await withSSOEnvironment(
            cacheKey: "my-sso",
            tokenJSON: makeModernTokenJSON(expiresIn: 2 * 3600)  // well outside refresh window
        ) { env in
            let requestCounter = RequestCounter()
            let mockHTTPClient = MockAWSHTTPClient { request in
                await requestCounter.record(request.url.absoluteString)
                return Self.makeRoleCredentialsResponse(accessKeyId: "AKIAVALID")
            }

            let provider = SSOCredentialProvider(configuration: self.makeModernConfig(), httpClient: mockHTTPClient)
            let credential = try await provider.getCredential(logger: self.logger)

            // Only one request (GetRoleCredentials), no OIDC refresh
            let urls = await requestCounter.urls
            #expect(urls.count == 1)
            #expect(urls[0].contains("portal.sso"))
            #expect(!urls[0].contains("oidc"))
            #expect(credential.accessKeyId == "AKIAVALID")
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

    @Test("Provider is immutable")
    func providerIsImmutable() throws {
        let provider = SSOCredentialProvider(profileName: "test", httpClient: MockAWSHTTPClient())
        #expect(provider.description.contains("SSOCredentialProvider"))
    }

    // MARK: - Fixture Builders

    /// Build a legacy SSOConfiguration (no session name, no refresh)
    private func makeLegacyConfig(
        startUrl: String = "https://test.awsapps.com/start",
        ssoRegion: Region = .useast1,
        accountId: String = "123456789012",
        roleName: String = "TestRole"
    ) -> SSOConfiguration {
        SSOConfiguration(
            ssoStartUrl: startUrl,
            ssoRegion: ssoRegion,
            ssoAccountId: accountId,
            ssoRoleName: roleName,
            region: ssoRegion,
            sessionName: nil
        )
    }

    /// Build a modern SSOConfiguration (with session name, supports refresh)
    private func makeModernConfig(
        startUrl: String = "https://test.awsapps.com/start",
        ssoRegion: Region = .useast1,
        accountId: String = "123456789012",
        roleName: String = "TestRole",
        sessionName: String = "my-sso"
    ) -> SSOConfiguration {
        SSOConfiguration(
            ssoStartUrl: startUrl,
            ssoRegion: ssoRegion,
            ssoAccountId: accountId,
            ssoRoleName: roleName,
            region: ssoRegion,
            sessionName: sessionName
        )
    }

    /// Build a modern token JSON with refresh fields.
    /// Token expires within the 15-min refresh window by default (triggers refresh).
    private func makeModernTokenJSON(
        accessToken: String = "test-access-token",
        expiresIn: TimeInterval = 10 * 60,
        refreshToken: String = "refresh-token-value",
        clientId: String = "client-id",
        clientSecret: String = "client-secret",
        registrationExpiresIn: TimeInterval = 90 * 24 * 3600
    ) -> String {
        """
        {
            "accessToken": "\(accessToken)",
            "expiresAt": "\(iso8601(offsetFromNow: expiresIn))",
            "refreshToken": "\(refreshToken)",
            "clientId": "\(clientId)",
            "clientSecret": "\(clientSecret)",
            "registrationExpiresAt": "\(iso8601(offsetFromNow: registrationExpiresIn))",
            "startUrl": "https://test.awsapps.com/start",
            "region": "us-east-1"
        }
        """
    }

    /// Build a successful GetRoleCredentials response
    private static func makeRoleCredentialsResponse(
        accessKeyId: String = "AKIATEST123",
        secretAccessKey: String = "testsecret",
        sessionToken: String = "testsession"
    ) -> (HTTPResponseStatus, Data) {
        let json = """
            {
                "roleCredentials": {
                    "accessKeyId": "\(accessKeyId)",
                    "secretAccessKey": "\(secretAccessKey)",
                    "sessionToken": "\(sessionToken)",
                    "expiration": \(Int64(Date(timeIntervalSinceNow: 3600).timeIntervalSince1970 * 1000))
                }
            }
            """
        return (.ok, json.data(using: .utf8)!)
    }

    /// Build a successful SSO-OIDC CreateToken refresh response
    private static func makeCreateTokenResponse(
        accessToken: String = "refreshed-access-token",
        refreshToken: String = "new-refresh-token"
    ) -> (HTTPResponseStatus, Data) {
        let json = """
            {
                "accessToken": "\(accessToken)",
                "expiresIn": 28800,
                "tokenType": "Bearer",
                "refreshToken": "\(refreshToken)"
            }
            """
        return (.ok, json.data(using: .utf8)!)
    }

    // MARK: - Test Environment Helpers

    /// Context passed to test closures by `withSSOEnvironment`
    struct TestEnvironment {
        let tempDirectory: URL
        let tokenPath: URL?
        let configPath: String?
    }

    /// Set up a temp directory with a token cache file and HOME override.
    /// Optionally writes a config file.
    private func withSSOEnvironment<T>(
        cacheKey: String,
        expiresIn: TimeInterval = 3600,
        accessToken: String = "test-access-token",
        configContent: String? = nil,
        body: (TestEnvironment) async throws -> T
    ) async throws -> T {
        let tokenJSON = """
            {
                "accessToken": "\(accessToken)",
                "expiresAt": "\(iso8601(offsetFromNow: expiresIn))"
            }
            """
        return try await withSSOEnvironment(
            cacheKey: cacheKey,
            rawTokenJSON: tokenJSON,
            configContent: configContent,
            body: body
        )
    }

    /// Set up a temp directory with an explicit token JSON and HOME override.
    /// Optionally writes a config file.
    private func withSSOEnvironment<T>(
        cacheKey: String,
        tokenJSON: String,
        configContent: String? = nil,
        body: (TestEnvironment) async throws -> T
    ) async throws -> T {
        try await withSSOEnvironment(
            cacheKey: cacheKey,
            rawTokenJSON: tokenJSON,
            configContent: configContent,
            body: body
        )
    }

    /// Core environment setup: temp directory + token cache + HOME override + optional config file.
    private func withSSOEnvironment<T>(
        cacheKey: String,
        rawTokenJSON: String,
        configContent: String? = nil,
        body: (TestEnvironment) async throws -> T
    ) async throws -> T {
        try await withTempDirectory { tempDirectory in
            let cacheDir = tempDirectory.appendingPathComponent(".aws/sso/cache")
            try FileManager.default.createDirectory(at: cacheDir, withIntermediateDirectories: true)
            let tokenPath = try self.createTokenFile(cacheKey: cacheKey, tokenJSON: rawTokenJSON, inDirectory: cacheDir)

            var configPath: String?
            if let configContent {
                let configURL = tempDirectory.appendingPathComponent("config")
                try configContent.write(to: configURL, atomically: true, encoding: .utf8)
                configPath = configURL.path
            }

            return try await self.withEnvironmentVariables(["HOME": tempDirectory.path]) {
                let env = TestEnvironment(tempDirectory: tempDirectory, tokenPath: tokenPath, configPath: configPath)
                return try await body(env)
            }
        }
    }

    /// Write a config file to a temp directory and pass its path to the body.
    private func withConfigFile<T>(_ content: String, body: (String) async throws -> T) async throws -> T {
        try await withTempDirectory { tempDirectory in
            let configURL = tempDirectory.appendingPathComponent("config")
            try content.write(to: configURL, atomically: true, encoding: .utf8)
            return try await body(configURL.path)
        }
    }

    // MARK: - Low-Level Helpers

    private func iso8601(offsetFromNow seconds: TimeInterval) -> String {
        ISO8601DateFormatter().string(from: Date(timeIntervalSinceNow: seconds))
    }

    private func withTempDirectory<T>(_ body: (URL) async throws -> T) async throws -> T {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }
        return try await body(tempDir)
    }

    /// Create a token file at the expected cache path for the given cache key (session name or start URL)
    @discardableResult
    private func createTokenFile(cacheKey: String, tokenJSON: String, inDirectory directory: URL) throws -> URL {
        let hash = Insecure.SHA1.hash(data: Data(cacheKey.utf8))
            .compactMap { String(format: "%02x", $0) }.joined()
        let tokenPath = directory.appendingPathComponent("\(hash).json")
        try tokenJSON.write(to: tokenPath, atomically: true, encoding: .utf8)
        return tokenPath
    }

    /// Sets environment variables for the duration of `body`, then restores originals.
    private func withEnvironmentVariables<T>(_ env: [String: String], body: () async throws -> T) async throws -> T {
        var saved: [String: String?] = [:]
        for key in env.keys {
            saved[key] = ProcessInfo.processInfo.environment[key]
        }
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
