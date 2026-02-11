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

// Test proper error handling for expired tokens

import Crypto
import Foundation
import Logging
import NIOCore
import NIOHTTP1
import SotoCore
import Testing

@testable import SotoCore

@Suite("Login Error Handling Tests", .serialized)
final class LoginErrorHandlingTests {

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

    @Test("Handle TOKEN_EXPIRED error correctly")
    func handleTokenExpiredError() async throws {
        let tempDirectory = try createTempDirectory()
        defer { removeTempDirectory(tempDirectory) }

        let privateKey = P256.Signing.PrivateKey()
        let pemKey = privateKey.pemRepresentation
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
                "refreshToken": "expired-refresh-token",
                "dpopKey": "\(escapedPemKey)",
                "clientId": "client-id-123",
                "idToken": "id-token-123",
                "tokenType": "urn:aws:params:oauth:token-type:access_token_sigv4"
            }
            """

        let sessionData = Data("test-session".utf8)
        let hash = SHA256.hash(data: sessionData)
        let hashString = hash.compactMap { String(format: "%02x", $0) }.joined()
        let tokenPath = tempDirectory.appendingPathComponent("\(hashString).json")
        try tokenData.write(to: tokenPath, atomically: true, encoding: .utf8)

        // Setup mock HTTP client
        // Mock server returns TOKEN_EXPIRED error
        let mockHTTPClient = MockAWSHTTPClient { request in
            let errorResponse = """
                {"error":"TOKEN_EXPIRED","message":"The refresh token has expired."}
                """
            return (.forbidden, errorResponse.data(using: .utf8)!)
        }

        let provider = try LoginCredentialProvider.create(
            loginSession: "test-session",
            loginRegion: .useast1,
            cacheDirectoryOverride: tempDirectory.path,
            httpClient: mockHTTPClient
        )

        let logger = Logger(label: "test")

        // Should throw tokenRefreshFailed with appropriate message
        do {
            _ = try await provider.getCredential(logger: logger)
            Issue.record("Expected tokenRefreshFailed error")
        } catch let error as AWSLoginCredentialError {
            #expect(error.code == "tokenRefreshFailed")
            #expect(error.message.contains("expired"))
            #expect(error.message.contains("reauthenticate"))
        } catch {
            Issue.record("Unexpected error type: \(error)")
        }
    }

    @Test("Handle USER_CREDENTIALS_CHANGED error correctly")
    func handleUserCredentialsChangedError() async throws {
        let tempDirectory = try createTempDirectory()
        defer { removeTempDirectory(tempDirectory) }

        let privateKey = P256.Signing.PrivateKey()
        let pemKey = privateKey.pemRepresentation
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
                "clientId": "client-id-123",
                "idToken": "id-token-123",
                "tokenType": "urn:aws:params:oauth:token-type:access_token_sigv4"
            }
            """

        let sessionData = Data("test-session".utf8)
        let hash = SHA256.hash(data: sessionData)
        let hashString = hash.compactMap { String(format: "%02x", $0) }.joined()
        let tokenPath = tempDirectory.appendingPathComponent("\(hashString).json")
        try tokenData.write(to: tokenPath, atomically: true, encoding: .utf8)

        // Setup mock HTTP client
        let mockHTTPClient = MockAWSHTTPClient { request in
            let errorResponse = """
                {"error":"USER_CREDENTIALS_CHANGED","message":"User credentials have changed."}
                """
            return (.forbidden, errorResponse.data(using: .utf8)!)
        }

        let provider = try LoginCredentialProvider.create(
            loginSession: "test-session",
            loginRegion: .useast1,
            cacheDirectoryOverride: tempDirectory.path,
            httpClient: mockHTTPClient
        )

        let logger = Logger(label: "test")

        do {
            _ = try await provider.getCredential(logger: logger)
            Issue.record("Expected tokenRefreshFailed error")
        } catch let error as AWSLoginCredentialError {
            #expect(error.code == "tokenRefreshFailed")
            #expect(error.message.contains("password"))
        } catch {
            Issue.record("Unexpected error type: \(error)")
        }
    }

    @Test("Handle INSUFFICIENT_PERMISSIONS error correctly")
    func handleInsufficientPermissionsError() async throws {
        let tempDirectory = try createTempDirectory()
        defer { removeTempDirectory(tempDirectory) }

        let privateKey = P256.Signing.PrivateKey()
        let pemKey = privateKey.pemRepresentation
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
                "clientId": "client-id-123",
                "idToken": "id-token-123",
                "tokenType": "urn:aws:params:oauth:token-type:access_token_sigv4"
            }
            """

        let sessionData = Data("test-session".utf8)
        let hash = SHA256.hash(data: sessionData)
        let hashString = hash.compactMap { String(format: "%02x", $0) }.joined()
        let tokenPath = tempDirectory.appendingPathComponent("\(hashString).json")
        try tokenData.write(to: tokenPath, atomically: true, encoding: .utf8)

        // Setup mock HTTP client
        let mockHTTPClient = MockAWSHTTPClient { request in
            let errorResponse = """
                {"error":"INSUFFICIENT_PERMISSIONS","message":"Insufficient permissions."}
                """
            return (.forbidden, errorResponse.data(using: .utf8)!)
        }

        let provider = try LoginCredentialProvider.create(
            loginSession: "test-session",
            loginRegion: .useast1,
            cacheDirectoryOverride: tempDirectory.path,
            httpClient: mockHTTPClient
        )

        let logger = Logger(label: "test")

        do {
            _ = try await provider.getCredential(logger: logger)
            Issue.record("Expected tokenRefreshFailed error")
        } catch let error as AWSLoginCredentialError {
            #expect(error.code == "tokenRefreshFailed")
            #expect(error.message.contains("permissions"))
            #expect(error.message.contains("CreateOAuth2Token"))
        } catch {
            Issue.record("Unexpected error type: \(error)")
        }
    }
}
