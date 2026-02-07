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

// Token File Manager Tests

import Crypto
import Foundation
import NIOCore
import NIOPosix
import Testing

@testable import SotoCore

@Suite("Token File Manager")
final class TokenFileManagerTests {
    let manager = TokenFileManager()

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

    @Test("Construct token path with custom directory")
    func constructTokenPath() throws {
        let tempDirectory = try createTempDirectory()
        defer { removeTempDirectory(tempDirectory) }

        let path = try manager.constructTokenPath(
            loginSession: "test-session",
            cacheDirectory: tempDirectory.path
        )

        // Should use SHA256 hash of "test-session"
        let sessionData = Data("test-session".utf8)
        let hash = SHA256.hash(data: sessionData)
        let hashString = hash.compactMap { String(format: "%02x", $0) }.joined()

        #expect(path.contains("\(hashString).json"))
        #expect(path.hasPrefix(tempDirectory.path))
    }

    @Test("Construct token path with home directory")
    func constructTokenPathWithHomeDirectory() throws {
        let path = try manager.constructTokenPath(
            loginSession: "test-session",
            cacheDirectory: nil
        )

        // Should use SHA256 hash
        let sessionData = Data("test-session".utf8)
        let hash = SHA256.hash(data: sessionData)
        let hashString = hash.compactMap { String(format: "%02x", $0) }.joined()

        #expect(path.contains(".aws/login/cache"))
        #expect(path.contains("\(hashString).json"))
    }

    @Test("Load and save token preserves all fields including idToken")
    func loadAndSaveToken() async throws {
        let tempDirectory = try createTempDirectory()
        defer { removeTempDirectory(tempDirectory) }

        // Create a test token file
        let privateKey = P256.Signing.PrivateKey()
        let pemKey = privateKey.pemRepresentation

        // Properly escape the PEM key for JSON
        let escapedPemKey = pemKey.replacing("\n", with: "\\n")

        let tokenData = """
            {
                "accessToken": {
                    "accessKeyId": "AKIATEST123",
                    "secretAccessKey": "secret123",
                    "sessionToken": "session123",
                    "accountId": "123456789012",
                    "expiresAt": "2026-12-31T23:59:59Z"
                },
                "refreshToken": "refresh123",
                "dpopKey": "\(escapedPemKey)",
                "clientId": "client123",
                "idToken": "idtoken123",
                "tokenType": "urn:aws:params:oauth:token-type:access_token_sigv4"
            }
            """

        let tokenPath = tempDirectory.appendingPathComponent("test-token.json").path
        try tokenData.write(toFile: tokenPath, atomically: true, encoding: .utf8)

        // Load token
        let fileIO = NonBlockingFileIO(threadPool: .singleton)
        let token = try await manager.loadToken(from: tokenPath, fileIO: fileIO)

        // Verify loaded values
        #expect(token.refreshToken == "refresh123")
        #expect(token.accountId == "123456789012")
        #expect(token.clientId == "client123")
        #expect(token.idToken == "idtoken123")
        #expect(token.accessKeyId == "AKIATEST123")

        // Create updated token with new credentials
        let updatedToken = token.withUpdatedCredentials(
            accessKeyId: "AKIANEW456",
            secretAccessKey: "newsecret456",
            sessionToken: "newsession456",
            expiresAt: Date(timeIntervalSince1970: 1_735_689_599),
            refreshToken: "newrefresh456"
        )

        // Save updated token
        let newTokenPath = tempDirectory.appendingPathComponent("updated-token.json").path
        try manager.saveToken(updatedToken, to: newTokenPath)

        // Verify saved file
        let savedData = try Data(contentsOf: URL(fileURLWithPath: newTokenPath))
        let savedJSON = try JSONSerialization.jsonObject(with: savedData) as! [String: Any]

        let accessToken = savedJSON["accessToken"] as! [String: Any]
        #expect(accessToken["accessKeyId"] as? String == "AKIANEW456")
        #expect(accessToken["secretAccessKey"] as? String == "newsecret456")
        #expect(accessToken["sessionToken"] as? String == "newsession456")
        #expect(savedJSON["refreshToken"] as? String == "newrefresh456")
        #expect(savedJSON["idToken"] as? String == "idtoken123")  // Preserved
    }

    @Test("Load token from nonexistent file throws error")
    func loadTokenFileNotFound() async throws {
        let fileIO = NonBlockingFileIO(threadPool: .singleton)
        do {
            _ = try await manager.loadToken(from: "/nonexistent/path/token.json", fileIO: fileIO)
            Issue.record("Expected tokenLoadFailed error")
        } catch let error as AWSLoginCredentialError {
            #expect(error.code == "tokenLoadFailed")
            #expect(error.message.contains("Cannot read token file"))
        } catch {
            Issue.record("Unexpected error type: \(error)")
        }
    }

    @Test("Load token with invalid JSON throws error")
    func loadTokenInvalidJSON() async throws {
        let tempDirectory = try createTempDirectory()
        defer { removeTempDirectory(tempDirectory) }

        let invalidJSON = "{ invalid json }"
        let tokenPath = tempDirectory.appendingPathComponent("invalid.json").path
        try invalidJSON.write(toFile: tokenPath, atomically: true, encoding: .utf8)

        let fileIO = NonBlockingFileIO(threadPool: .singleton)
        do {
            _ = try await manager.loadToken(from: tokenPath, fileIO: fileIO)
            Issue.record("Expected tokenParseFailed error")
        } catch let error as AWSLoginCredentialError {
            #expect(error.code == "tokenParseFailed")
        } catch {
            Issue.record("Unexpected error type: \(error)")
        }
    }
}
