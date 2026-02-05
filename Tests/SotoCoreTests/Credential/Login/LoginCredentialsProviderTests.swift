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

// Login Credentials Provider Tests

import Crypto
import Foundation
import Logging
import NIOCore
import NIOHTTP1
import Testing

@testable import SotoCore

@Suite("Login Credentials Provider", .serialized)
final class LoginCredentialsProviderTests {

    // Helper to create a unique temp directory for each test
    func createTempDirectory() throws -> URL {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        return tempDir
    }

    // Helper to clean up temp directory
    func removeTempDirectory(_ url: URL) {
        try? FileManager.default.removeItem(at: url)
    }

    @Test("Get credentials successfully with full flow")
    func getCredentialsSuccess() async throws {
        let tempDirectory = try createTempDirectory()
        defer { removeTempDirectory(tempDirectory) }

        // Setup token file
        let privateKey = P256.Signing.PrivateKey()
        let pemKey = privateKey.pemRepresentation

        // Properly escape the PEM key for JSON
        let escapedPemKey = pemKey.replacing("\n", with: "\\n")

        let tokenData = """
            {
                "accessToken": {
                    "accessKeyId": "AKIAOLD123",
                    "secretAccessKey": "oldsecret",
                    "sessionToken": "oldsession",
                    "accountId": "123456789012",
                    "expiresAt": "2025-12-31T23:59:59Z"
                },
                "refreshToken": "refresh-token-123",
                "dpopKey": "\(escapedPemKey)",
                "clientId": "client-id-123",
                "idToken": "id-token-123",
                "tokenType": "urn:aws:params:oauth:token-type:access_token_sigv4"
            }
            """

        // Calculate SHA256 hash of login session
        let sessionData = Data("test-session".utf8)
        let hash = SHA256.hash(data: sessionData)
        let hashString = hash.compactMap { String(format: "%02x", $0) }.joined()

        let tokenPath = tempDirectory.appendingPathComponent("\(hashString).json")
        try tokenData.write(to: tokenPath, atomically: true, encoding: .utf8)

        // Setup mock HTTP client and response
        let mockHTTPClient = MockAWSHTTPClient { request in
            // Verify request
            #expect(request.method == .POST)
            #expect(request.headers["Content-Type"].first == "application/json")
            #expect(request.headers["DPoP"].first != nil)
            #expect(request.headers["Host"].first == "us-east-1.signin.aws.amazon.com")

            // Verify request body
            let bodyBuffer = try await request.body.collect(upTo: 1024 * 1024)
            let bodyData = Data(buffer: bodyBuffer)
            let json = try JSONSerialization.jsonObject(with: bodyData) as! [String: String]
            #expect(json["clientId"] == "client-id-123")
            #expect(json["refreshToken"] == "refresh-token-123")
            #expect(json["grantType"] == "refresh_token")

            // Return mock response
            let responseJSON = """
                {
                    "accessToken": {
                        "accessKeyId": "AKIANEW456",
                        "secretAccessKey": "newsecret456",
                        "sessionToken": "newsession456"
                    },
                    "tokenType": "urn:aws:params:oauth:token-type:access_token_sigv4",
                    "expiresIn": 3600,
                    "refreshToken": "new-refresh-token-456"
                }
                """

            return (.ok, responseJSON.data(using: .utf8)!)
        }

        // Create provider
        let provider = try LoginCredentialsProvider.create(
            loginSession: "test-session",
            loginRegion: .useast1,
            cacheDirectoryOverride: tempDirectory.path,
            httpClient: mockHTTPClient
        )

        // Get credentials
        let logger = Logger(label: "test")
        let credential = try await provider.getCredential(logger: logger)

        // Verify credentials
        #expect(credential.accessKeyId == "AKIANEW456")
        #expect(credential.secretAccessKey == "newsecret456")
        #expect(credential.sessionToken == "newsession456")

        // Verify it's an expiring credential
        if let expiringCredential = credential as? ExpiringCredential {
            #expect(expiringCredential.expiration > Date())
        } else {
            Issue.record("Expected ExpiringCredential")
        }

        // Verify token file was updated
        let updatedTokenData = try Data(contentsOf: tokenPath)
        let updatedJSON = try JSONSerialization.jsonObject(with: updatedTokenData) as! [String: Any]
        #expect(updatedJSON["refreshToken"] as? String == "new-refresh-token-456")
        #expect(updatedJSON["idToken"] as? String == "id-token-123")  // Preserved

        let updatedAccessToken = updatedJSON["accessToken"] as! [String: Any]
        #expect(updatedAccessToken["accessKeyId"] as? String == "AKIANEW456")
    }

    @Test("Get credentials with HTTP error returns proper error")
    func getCredentialsHTTPError() async throws {
        let tempDirectory = try createTempDirectory()
        defer { removeTempDirectory(tempDirectory) }

        // Setup token file
        let privateKey = P256.Signing.PrivateKey()
        let pemKey = privateKey.pemRepresentation

        // Properly escape the PEM key for JSON
        let escapedPemKey = pemKey.replacing("\n", with: "\\n")

        let tokenData = """
            {
                "accessToken": {
                    "accessKeyId": "AKIAOLD123",
                    "secretAccessKey": "oldsecret",
                    "sessionToken": "oldsession",
                    "accountId": "123456789012",
                    "expiresAt": "2020-01-01T00:00:00Z"
                },
                "refreshToken": "refresh-token",
                "dpopKey": "\(escapedPemKey)",
                "clientId": "client-id",
                "idToken": "id-token",
                "tokenType": "urn:aws:params:oauth:token-type:access_token_sigv4"
            }
            """

        // Calculate SHA256 hash of login session
        let sessionData = Data("test-session".utf8)
        let hash = SHA256.hash(data: sessionData)
        let hashString = hash.compactMap { String(format: "%02x", $0) }.joined()

        let tokenPath = tempDirectory.appendingPathComponent("\(hashString).json")
        try tokenData.write(to: tokenPath, atomically: true, encoding: .utf8)

        // Setup mock HTTP client and response
        let mockHTTPClient = MockAWSHTTPClient { request in
            (.badRequest, Data())
        }

        // Create provider
        let provider = try LoginCredentialsProvider.create(
            loginSession: "test-session",
            loginRegion: .useast1,
            cacheDirectoryOverride: tempDirectory.path,
            httpClient: mockHTTPClient
        )

        // Expect error - use await with throws expectation
        let logger = Logger(label: "test")
        await #expect(throws: LoginError.self) {
            try await provider.getCredential(logger: logger)
        }
    }

    @Test("Get credentials with invalid response throws decoding error")
    func getCredentialsInvalidResponse() async throws {
        let tempDirectory = try createTempDirectory()
        defer { removeTempDirectory(tempDirectory) }

        // Setup token file
        let privateKey = P256.Signing.PrivateKey()
        let pemKey = privateKey.pemRepresentation

        // Properly escape the PEM key for JSON
        let escapedPemKey = pemKey.replacing("\n", with: "\\n")

        let tokenData = """
            {
                "accessToken": {
                    "accessKeyId": "AKIAOLD123",
                    "secretAccessKey": "oldsecret",
                    "sessionToken": "oldsession",
                    "accountId": "123456789012",
                    "expiresAt": "2020-01-01T00:00:00Z"
                },
                "refreshToken": "refresh-token",
                "dpopKey": "\(escapedPemKey)",
                "clientId": "client-id",
                "idToken": "id-token",
                "tokenType": "urn:aws:params:oauth:token-type:access_token_sigv4"
            }
            """

        // Calculate SHA256 hash of login session
        let sessionData = Data("test-session".utf8)
        let hash = SHA256.hash(data: sessionData)
        let hashString = hash.compactMap { String(format: "%02x", $0) }.joined()

        let tokenPath = tempDirectory.appendingPathComponent("\(hashString).json")
        try tokenData.write(to: tokenPath, atomically: true, encoding: .utf8)

        // Setup mock HTTP client and  mock response with invalid JSON
        let mockHTTPClient = MockAWSHTTPClient { request in
            (.ok, "invalid json".data(using: .utf8)!)
        }

        // Create provider
        let provider = try LoginCredentialsProvider.create(
            loginSession: "test-session",
            loginRegion: .useast1,
            cacheDirectoryOverride: tempDirectory.path,
            httpClient: mockHTTPClient
        )

        // Expect decoding error - use await with throws expectation
        let logger = Logger(label: "test")
        await #expect(throws: DecodingError.self) {
            try await provider.getCredential(logger: logger)
        }
    }

    @Test("Get credentials with missing token file throws error")
    func getCredentialsTokenFileNotFound() async throws {
        let tempDirectory = try createTempDirectory()
        defer { removeTempDirectory(tempDirectory) }

        // Create provider without token file
        let provider = try LoginCredentialsProvider.create(
            loginSession: "nonexistent-session",
            loginRegion: .useast1,
            cacheDirectoryOverride: tempDirectory.path,
            httpClient: MockAWSHTTPClient()
        )

        // Expect error - use await with throws expectation for the error type
        let logger = Logger(label: "test")
        await #expect(throws: LoginError.self) {
            try await provider.getCredential(logger: logger)
        }
    }

    @Test("Get credentials returns cached token when not expired")
    func getCredentialsCachedToken() async throws {
        let tempDirectory = try createTempDirectory()
        defer { removeTempDirectory(tempDirectory) }

        // Setup token file with future expiration
        let privateKey = P256.Signing.PrivateKey()
        let pemKey = privateKey.pemRepresentation
        let escapedPemKey = pemKey.replacing("\n", with: "\\n")

        // Set expiration to 1 hour in the future
        let futureDate = Date(timeIntervalSinceNow: 3600)
        let formatter = ISO8601DateFormatter()
        let expiresAtString = formatter.string(from: futureDate)

        let tokenData = """
            {
                "accessToken": {
                    "accessKeyId": "AKIACACHED123",
                    "secretAccessKey": "cachedsecret",
                    "sessionToken": "cachedsession",
                    "accountId": "123456789012",
                    "expiresAt": "\(expiresAtString)"
                },
                "refreshToken": "refresh-token-123",
                "dpopKey": "\(escapedPemKey)",
                "clientId": "client-id-123",
                "idToken": "id-token-123",
                "tokenType": "urn:aws:params:oauth:token-type:access_token_sigv4"
            }
            """

        // Calculate SHA256 hash of login session
        let sessionData = Data("test-session".utf8)
        let hash = SHA256.hash(data: sessionData)
        let hashString = hash.compactMap { String(format: "%02x", $0) }.joined()

        let tokenPath = tempDirectory.appendingPathComponent("\(hashString).json")
        try tokenData.write(to: tokenPath, atomically: true, encoding: .utf8)

        // Setup mock HTTP client - - should not make any requests
        let mockHTTPClient = MockAWSHTTPClient { _ in
            Issue.record("Should not make HTTP request for valid cached token")
            return (.ok, Data())
        }

        // Create provider
        let provider = try LoginCredentialsProvider.create(
            loginSession: "test-session",
            loginRegion: .useast1,
            cacheDirectoryOverride: tempDirectory.path,
            httpClient: mockHTTPClient
        )

        // Get credentials - should return cached without refresh
        let logger = Logger(label: "test")
        let credential = try await provider.getCredential(logger: logger)

        // Verify cached credentials were returned
        #expect(credential.accessKeyId == "AKIACACHED123")
        #expect(credential.secretAccessKey == "cachedsecret")
        #expect(credential.sessionToken == "cachedsession")
    }

    @Test("Token validation fails when clientId is missing")
    func tokenValidationMissingClientId() async throws {
        let tempDirectory = try createTempDirectory()
        defer { removeTempDirectory(tempDirectory) }

        let privateKey = P256.Signing.PrivateKey()
        let pemKey = privateKey.pemRepresentation
        let escapedPemKey = pemKey.replacing("\n", with: "\\n")

        let tokenData = """
            {
                "accessToken": {
                    "accessKeyId": "AKIATEST123",
                    "secretAccessKey": "secret",
                    "sessionToken": "session",
                    "accountId": "123456789012",
                    "expiresAt": "2020-01-01T00:00:00Z"
                },
                "refreshToken": "refresh-token",
                "dpopKey": "\(escapedPemKey)",
                "clientId": "",
                "idToken": "id-token",
                "tokenType": "urn:aws:params:oauth:token-type:access_token_sigv4"
            }
            """

        let sessionData = Data("test-session".utf8)
        let hash = SHA256.hash(data: sessionData)
        let hashString = hash.compactMap { String(format: "%02x", $0) }.joined()

        let tokenPath = tempDirectory.appendingPathComponent("\(hashString).json")
        try tokenData.write(to: tokenPath, atomically: true, encoding: .utf8)

        // Setup mock HTTP client
        let provider = try LoginCredentialsProvider.create(
            loginSession: "test-session",
            loginRegion: .useast1,
            cacheDirectoryOverride: tempDirectory.path,
            httpClient: MockAWSHTTPClient()
        )

        let logger = Logger(label: "test")
        await #expect(throws: LoginError.self) {
            try await provider.getCredential(logger: logger)
        }
    }

    @Test("Token validation fails when refreshToken is missing")
    func tokenValidationMissingRefreshToken() async throws {
        let tempDirectory = try createTempDirectory()
        defer { removeTempDirectory(tempDirectory) }

        let privateKey = P256.Signing.PrivateKey()
        let pemKey = privateKey.pemRepresentation
        let escapedPemKey = pemKey.replacing("\n", with: "\\n")

        let tokenData = """
            {
                "accessToken": {
                    "accessKeyId": "AKIATEST123",
                    "secretAccessKey": "secret",
                    "sessionToken": "session",
                    "accountId": "123456789012",
                    "expiresAt": "2020-01-01T00:00:00Z"
                },
                "refreshToken": "",
                "dpopKey": "\(escapedPemKey)",
                "clientId": "client-id",
                "idToken": "id-token",
                "tokenType": "urn:aws:params:oauth:token-type:access_token_sigv4"
            }
            """

        let sessionData = Data("test-session".utf8)
        let hash = SHA256.hash(data: sessionData)
        let hashString = hash.compactMap { String(format: "%02x", $0) }.joined()

        let tokenPath = tempDirectory.appendingPathComponent("\(hashString).json")
        try tokenData.write(to: tokenPath, atomically: true, encoding: .utf8)

        let provider = try LoginCredentialsProvider.create(
            loginSession: "test-session",
            loginRegion: .useast1,
            cacheDirectoryOverride: tempDirectory.path,
            httpClient: MockAWSHTTPClient()
        )

        let logger = Logger(label: "test")
        await #expect(throws: LoginError.self) {
            try await provider.getCredential(logger: logger)
        }
    }

    @Test("Token validation fails when dpopKey is missing")
    func tokenValidationMissingDpopKey() async throws {
        let tempDirectory = try createTempDirectory()
        defer { removeTempDirectory(tempDirectory) }

        let tokenData = """
            {
                "accessToken": {
                    "accessKeyId": "AKIATEST123",
                    "secretAccessKey": "secret",
                    "sessionToken": "session",
                    "accountId": "123456789012",
                    "expiresAt": "2020-01-01T00:00:00Z"
                },
                "refreshToken": "refresh-token",
                "dpopKey": "",
                "clientId": "client-id",
                "idToken": "id-token",
                "tokenType": "urn:aws:params:oauth:token-type:access_token_sigv4"
            }
            """

        let sessionData = Data("test-session".utf8)
        let hash = SHA256.hash(data: sessionData)
        let hashString = hash.compactMap { String(format: "%02x", $0) }.joined()

        let tokenPath = tempDirectory.appendingPathComponent("\(hashString).json")
        try tokenData.write(to: tokenPath, atomically: true, encoding: .utf8)

        let provider = try LoginCredentialsProvider.create(
            loginSession: "test-session",
            loginRegion: .useast1,
            cacheDirectoryOverride: tempDirectory.path,
            httpClient: MockAWSHTTPClient()
        )

        let logger = Logger(label: "test")
        await #expect(throws: LoginError.self) {
            try await provider.getCredential(logger: logger)
        }
    }

    @Test("Provider is immutable")
    func providerIsImmutable() throws {
        let tempDirectory = try createTempDirectory()
        defer { removeTempDirectory(tempDirectory) }

        let provider = try LoginCredentialsProvider.create(
            loginSession: "test-session",
            loginRegion: .useast1,
            cacheDirectoryOverride: tempDirectory.path,
            httpClient: MockAWSHTTPClient()
        )

        // Provider should be immutable - no var properties, no mutating methods
        // This test just verifies the provider can be created and used without mutation
        #expect(provider.description.contains("LoginCredentialsProvider"))
    }
}
