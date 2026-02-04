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

// Login Configuration

import Foundation

public enum LoginError: Error, Equatable {
    case loginSessionMissing
    case regionMissing
    case profileNotFound(String)
    case configFileNotFound(String)
    case tokenLoadFailed(String)
    case tokenParseFailed
    case endpointConstructionFailed
    case httpRequestFailed(String)
    case tokenRefreshFailed(String)
    case invalidResponse
    case tokenWriteFailed
}

struct LoginConfiguration {
    let endpoint: String
    let loginSession: String
    let region: Region
    let cacheDirectory: String?

    static let loginServiceHostPrefix = "signin"
    static let loginServiceName = "signin"
    static let loginEndpointPath = "/v1/token"
    static let cacheEnvVar = "AWS_LOGIN_CACHE_DIRECTORY"

    init(endpoint: String, loginSession: String, region: Region, cacheDirectory: String?) {
        self.endpoint = endpoint
        self.loginSession = loginSession
        self.region = region
        self.cacheDirectory = cacheDirectory
    }
}

struct LoginToken {
    let accessKeyId: String?
    let secretAccessKey: String?
    let sessionToken: String?
    let expiresAt: Date?
    let refreshToken: String
    let accountId: String
    let privateKey: String
    let publicKey: String
    let clientId: String
    let idToken: String

    init(
        accessKeyId: String? = nil,
        secretAccessKey: String? = nil,
        sessionToken: String? = nil,
        expiresAt: Date? = nil,
        refreshToken: String,
        accountId: String,
        privateKey: String,
        publicKey: String,
        clientId: String,
        idToken: String
    ) {
        self.accessKeyId = accessKeyId
        self.secretAccessKey = secretAccessKey
        self.sessionToken = sessionToken
        self.expiresAt = expiresAt
        self.refreshToken = refreshToken
        self.accountId = accountId
        self.privateKey = privateKey
        self.publicKey = publicKey
        self.clientId = clientId
        self.idToken = idToken
    }

    /// Create a new token with updated credentials
    func withUpdatedCredentials(
        accessKeyId: String,
        secretAccessKey: String,
        sessionToken: String,
        expiresAt: Date,
        refreshToken: String
    ) -> LoginToken {
        LoginToken(
            accessKeyId: accessKeyId,
            secretAccessKey: secretAccessKey,
            sessionToken: sessionToken,
            expiresAt: expiresAt,
            refreshToken: refreshToken,
            accountId: self.accountId,
            privateKey: self.privateKey,
            publicKey: self.publicKey,
            clientId: self.clientId,
            idToken: self.idToken
        )
    }
}
