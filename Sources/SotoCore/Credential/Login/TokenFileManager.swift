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

// Token File Management - Disk I/O for tokens

import Crypto
import NIOCore
import NIOPosix

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif

struct TokenFileManager {
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
            throw AWSLoginCredentialError.tokenLoadFailed("Cannot determine cache directory")
        }

        // SHA256 hash the login_session (after trimming whitespace) per spec
        let trimmedSession = loginSession.trimmingCharacters(in: .whitespaces)
        let sessionData = Data(trimmedSession.utf8)
        let hash = SHA256.hash(data: sessionData)
        let hashString = hash.compactMap { String(format: "%02x", $0) }.joined()

        return "\(baseDir)/\(hashString).json"
    }

    func loadToken(from path: String, fileIO: NonBlockingFileIO) async throws -> LoginToken {
        let byteBuffer: ByteBuffer
        do {
            byteBuffer = try await fileIO.withFileRegion(path: path) { fileRegion in
                try await fileIO.read(fileHandle: fileRegion.fileHandle, byteCount: fileRegion.readableBytes, allocator: ByteBufferAllocator())
            }
        } catch {
            throw AWSLoginCredentialError.tokenLoadFailed("Cannot read token file at \(path). Please authenticate with `aws login`.")
        }

        guard let data = byteBuffer.getData(at: 0, length: byteBuffer.readableBytes) else {
            throw AWSLoginCredentialError.tokenLoadFailed("Cannot read token file at \(path). Please authenticate with `aws login`.")
        }

        let decoder = JSONDecoder()
        guard let tokenData = try? decoder.decode(TokenFileData.self, from: data) else {
            throw AWSLoginCredentialError.tokenParseFailed
        }

        // Validate required fields are present per spec
        guard !tokenData.clientId.isEmpty else {
            throw AWSLoginCredentialError.tokenLoadFailed("Token missing required field: clientId")
        }
        guard !tokenData.refreshToken.isEmpty else {
            throw AWSLoginCredentialError.tokenLoadFailed("Token missing required field: refreshToken")
        }
        guard !tokenData.dpopKey.isEmpty else {
            throw AWSLoginCredentialError.tokenLoadFailed("Token missing required field: dpopKey")
        }

        // Extract public/private key from dpopKey (EC key in PEM format)
        let dpopKey = tokenData.dpopKey

        // Parse expiresAt if present
        var expiresAt: Date?
        if let accessToken = tokenData.accessToken, !accessToken.expiresAt.isEmpty {
            if #available(iOS 15, macOS 12, tvOS 15, watchOS 8, *) {
                expiresAt = try? Date(accessToken.expiresAt, strategy: .iso8601)
            } else {
                expiresAt = ISO8601DateFormatter().date(from: accessToken.expiresAt)
            }
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

    func saveToken(_ token: LoginToken, to path: String, fileIO: NonBlockingFileIO, threadPool: NIOThreadPool) async throws {
        // Parse ISO8601 date if we have expiresAt
        let expiresAtString: String
        if let expiresAt = token.expiresAt {
            if #available(iOS 15, macOS 12, tvOS 15, watchOS 8, *) {
                expiresAtString = expiresAt.formatted(.iso8601)
            } else {
                expiresAtString = ISO8601DateFormatter().string(from: expiresAt)
            }
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

        // Write using NonBlockingFileIO
        var buffer = ByteBufferAllocator().buffer(capacity: data.count)
        buffer.writeBytes(data)

        // Delete file if it exists to ensure clean write
        // Using unlink() through thread pool for non-blocking operation
        _ = try? await threadPool.runIfActive { unlink(path) }

        try await fileIO.withFileHandle(
            path: path,
            mode: .write,
            flags: .allowFileCreation(posixMode: 0o600)
        ) { fileHandle in
            try await fileIO.write(fileHandle: fileHandle, buffer: buffer)
        }
    }
}
