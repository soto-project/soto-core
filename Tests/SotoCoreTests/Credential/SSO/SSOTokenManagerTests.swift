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

// SSO Token Manager Tests (cache, refresh, path construction)

import Crypto
import Logging
import NIOCore
import NIOHTTP1
import Testing

@testable import SotoCore

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif

extension SSOCredentialProviderTests {

    // MARK: - Token Cache Tests

    @Test("Invalid token JSON throws invalidTokenFormat error")
    func invalidTokenJSON() async throws {
        try await withSSOEnvironment(cacheKey: "https://test.awsapps.com/start", tokenJSON: "{ not valid json") { env in
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

        try await withSSOEnvironment(cacheKey: "https://test.awsapps.com/start", tokenJSON: tokenJSON) { env in
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
        try await withTempCacheDirectory { cacheDirectory in
            // Use a cache directory but no token file
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

                    struct CreateTokenRequest: Decodable {
                        let grantType: String
                        let clientId: String
                        let refreshToken: String
                    }
                    let bodyBuffer = try await request.body.collect(upTo: 1024 * 1024)
                    let body = try JSONDecoder().decode(CreateTokenRequest.self, from: Data(buffer: bodyBuffer))
                    #expect(body.grantType == "refresh_token")
                    #expect(body.clientId == "client-id")
                    #expect(body.refreshToken == "refresh-token-value")

                    return self.makeCreateTokenResponse()
                } else {
                    #expect(request.headers["x-amz-sso_bearer_token"].first == "refreshed-access-token")
                    return self.makeRoleCredentialsResponse(
                        accessKeyId: "AKIAREFRESHED",
                        secretAccessKey: "refreshedsecret",
                        sessionToken: "refreshedsession"
                    )
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

    // MARK: - Token Path Construction Tests

    @Test("Token path uses SHA-1 hash of session name for modern format")
    func tokenPathModernFormat() throws {
        let tokenManager = SSOTokenManager(httpClient: MockAWSHTTPClient())
        let path = try tokenManager.constructTokenPath(config: makeModernConfig())

        let expectedHash = Insecure.SHA1.hash(data: Data("my-sso".utf8))
            .compactMap { String(format: "%02x", $0) }.joined()
        #expect(path.hasSuffix("\(expectedHash).json"))
        #expect(path.contains(Self.ssoCacheDirectory))
    }

    @Test("Token path uses SHA-1 hash of start URL for legacy format")
    func tokenPathLegacyFormat() throws {
        let tokenManager = SSOTokenManager(httpClient: MockAWSHTTPClient())
        let path = try tokenManager.constructTokenPath(config: makeLegacyConfig())

        let expectedHash = Insecure.SHA1.hash(data: Data("https://test.awsapps.com/start".utf8))
            .compactMap { String(format: "%02x", $0) }.joined()
        #expect(path.hasSuffix("\(expectedHash).json"))
        #expect(path.contains(Self.ssoCacheDirectory))
    }
}
