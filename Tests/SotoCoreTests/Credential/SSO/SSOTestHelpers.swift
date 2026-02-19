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

// Shared test helpers for SSO Credential Provider tests

import Crypto
import Logging
import NIOCore
import NIOHTTP1

@testable import SotoCore

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

// MARK: - Fixture Builders

extension SSOCredentialProviderTests {

    static let ssoCacheDirectory = ".aws/sso/cache"

    /// Build a legacy SSOConfiguration (no session name, no refresh)
    func makeLegacyConfig(
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
    func makeModernConfig(
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
    func makeModernTokenJSON(
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
    func makeRoleCredentialsResponse(
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
    func makeCreateTokenResponse(
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
}

// MARK: - Test Environment Helpers

extension SSOCredentialProviderTests {

    /// Context passed to test closures by `withSSOEnvironment`
    struct TestEnvironment {
        let tempDirectory: URL
        let tokenPath: URL?
        let configPath: String?
    }

    /// Set up a temp directory with a token cache file and HOME override.
    /// Optionally writes a config file.
    func withSSOEnvironment<T>(
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
            tokenJSON: tokenJSON,
            configContent: configContent,
            body: body
        )
    }

    /// Core environment setup: temp directory + token cache + HOME override + optional config file.
    func withSSOEnvironment<T>(
        cacheKey: String,
        tokenJSON: String,
        configContent: String? = nil,
        body: (TestEnvironment) async throws -> T
    ) async throws -> T {
        try await withTempCacheDirectory { cacheDir in
            let tokenPath = try self.createTokenFile(cacheKey: cacheKey, tokenJSON: tokenJSON, inDirectory: cacheDir)

            var configPath: String?
            if let configContent {
                let configURL = cacheDir.appendingPathComponent("config")
                try configContent.write(to: configURL, atomically: true, encoding: .utf8)
                configPath = configURL.path
            }

            let env = TestEnvironment(tempDirectory: cacheDir, tokenPath: tokenPath, configPath: configPath)
            return try await body(env)
        }
    }

    /// Create a `.aws/sso/cache` directory in a temporary directory
    /// and set the HOME env variable with the new temporary directory
    func withTempCacheDirectory<T>(body: (URL) async throws -> T) async throws -> T {
        try await withTempDirectory { tempDirectory in
            let cacheDir = tempDirectory.appendingPathComponent(Self.ssoCacheDirectory)
            try FileManager.default.createDirectory(at: cacheDir, withIntermediateDirectories: true)
            return try await self.withEnvironmentVariables(["HOME": tempDirectory.path]) {
                try await body(cacheDir)
            }
        }
    }

    /// Write a config file to a temp directory and pass its path to the body.
    func withConfigFile<T>(_ content: String, body: (String) async throws -> T) async throws -> T {
        try await withTempDirectory { tempDirectory in
            let configURL = tempDirectory.appendingPathComponent("config")
            try content.write(to: configURL, atomically: true, encoding: .utf8)
            return try await body(configURL.path)
        }
    }

    // MARK: - Low-Level Helpers

    func iso8601(offsetFromNow seconds: TimeInterval) -> String {
        ISO8601DateCoder.string(from: Date(timeIntervalSinceNow: seconds)) ?? ""
    }

    func withTempDirectory<T>(_ body: (URL) async throws -> T) async throws -> T {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }
        return try await body(tempDir)
    }

    /// Create a token file at the expected cache path for the given cache key (session name or start URL)
    @discardableResult
    func createTokenFile(cacheKey: String, tokenJSON: String, inDirectory directory: URL) throws -> URL {
        let hash = Insecure.SHA1.hash(data: Data(cacheKey.utf8))
            .compactMap { String(format: "%02x", $0) }.joined()
        let tokenPath = directory.appendingPathComponent("\(hash).json")
        try tokenJSON.write(to: tokenPath, atomically: true, encoding: .utf8)
        return tokenPath
    }

    /// Sets environment variables for the duration of `body`, then restores originals.
    func withEnvironmentVariables<T>(_ env: [String: String], body: () async throws -> T) async throws -> T {
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
actor RequestCounter {
    var urls: [String] = []

    func record(_ url: String) {
        urls.append(url)
    }
}
