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

// Token File Management - Disk I/O for tokens

import Crypto
import Foundation

struct TokenFileManager {
    private let fileManager = FileManager.default

    private struct AccessToken: Codable {
        let accessKeyId: String
        let secretAccessKey: String
        let sessionToken: String
        let accountId: String
        let expiresAt: String
    }

    private struct TokenFileData: Codable {
        let accessToken: AccessToken?
        let refreshToken: String
        let dpopKey: String
        let clientId: String
        let idToken: String
        let tokenType: String?
    }

    func constructTokenPath(loginSession: String, cacheDirectory: String?) throws -> String {
        let baseDir: String
        if let cacheDir = cacheDirectory {
            baseDir = cacheDir
        } else if let homeDir = ProcessInfo.processInfo.environment["HOME"] {
            baseDir = "\(homeDir)/.aws/login/cache"
        } else {
            throw LoginError.tokenLoadFailed("Cannot determine cache directory")
        }

        // SHA256 hash the login_session (after trimming whitespace) per spec
        let trimmedSession = loginSession.trimmingCharacters(in: .whitespaces)
        let sessionData = Data(trimmedSession.utf8)
        let hash = SHA256.hash(data: sessionData)
        let hashString = hash.compactMap { String(format: "%02x", $0) }.joined()

        return "\(baseDir)/\(hashString).json"
    }

    func loadToken(from path: String) throws -> LoginToken {
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: path)) else {
            throw LoginError.tokenLoadFailed("Cannot read token file at \(path). Please authenticate with `aws login`.")
        }

        let decoder = JSONDecoder()
        guard let tokenData = try? decoder.decode(TokenFileData.self, from: data) else {
            throw LoginError.tokenParseFailed
        }

        // Validate required fields are present per spec
        guard !tokenData.clientId.isEmpty else {
            throw LoginError.tokenLoadFailed("Token missing required field: clientId")
        }
        guard !tokenData.refreshToken.isEmpty else {
            throw LoginError.tokenLoadFailed("Token missing required field: refreshToken")
        }
        guard !tokenData.dpopKey.isEmpty else {
            throw LoginError.tokenLoadFailed("Token missing required field: dpopKey")
        }

        // Extract public/private key from dpopKey (EC key in PEM format)
        let dpopKey = tokenData.dpopKey

        // Parse expiresAt if present
        var expiresAt: Date?
        if let accessToken = tokenData.accessToken, !accessToken.expiresAt.isEmpty {
            let formatter = ISO8601DateFormatter()
            expiresAt = formatter.date(from: accessToken.expiresAt)
        }

        return LoginToken(
            accessKeyId: tokenData.accessToken?.accessKeyId,
            secretAccessKey: tokenData.accessToken?.secretAccessKey,
            sessionToken: tokenData.accessToken?.sessionToken,
            expiresAt: expiresAt,
            refreshToken: tokenData.refreshToken,
            accountId: tokenData.accessToken?.accountId ?? "",
            privateKey: dpopKey,
            publicKey: dpopKey,
            clientId: tokenData.clientId,
            idToken: tokenData.idToken
        )
    }

    func saveToken(_ token: LoginToken, to path: String) throws {
        // Parse ISO8601 date if we have expiresAt
        let expiresAtString: String
        if let expiresAt = token.expiresAt {
            let formatter = ISO8601DateFormatter()
            expiresAtString = formatter.string(from: expiresAt)
        } else {
            expiresAtString = ""
        }

        let accessToken = AccessToken(
            accessKeyId: token.accessKeyId ?? "",
            secretAccessKey: token.secretAccessKey ?? "",
            sessionToken: token.sessionToken ?? "",
            accountId: token.accountId,
            expiresAt: expiresAtString
        )

        let tokenData = TokenFileData(
            accessToken: accessToken,
            refreshToken: token.refreshToken,
            dpopKey: token.privateKey,
            clientId: token.clientId,
            idToken: token.idToken,
            tokenType: "urn:aws:params:oauth:token-type:access_token_sigv4"
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted
        let data = try encoder.encode(tokenData)
        try data.write(to: URL(fileURLWithPath: path))
    }
}
