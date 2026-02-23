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

// Note: The ideal pattern for error assertions in Swift Testing is:
//   let error = await #expect(throws: AWSSSOCredentialError.self) { ... }
//   #expect(error?.code == "expectedCode")
// However, the return-value variant of #expect(throws:) was introduced in Swift 6.1.
// On Swift 6.0 it returns Void, so we use the closure-based validation pattern instead:
//   await #expect { ... } throws: { error in (error as? AWSSSOCredentialError)?.code == "expectedCode" }

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

@Suite("SSO Credential Provider", .serialized)
final class SSOCredentialProviderTests: Sendable {

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
                return self.makeRoleCredentialsResponse()
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
            let credential = try await provider.getCredential(logger: self.logger)

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
                return self.makeRoleCredentialsResponse(accessKeyId: "AKIALEGACY", secretAccessKey: "legacysecret", sessionToken: "legacysession")
            }

            let provider = SSOCredentialProvider(configuration: self.makeLegacyConfig(), httpClient: mockHTTPClient)
            let credential = try await provider.getCredential(logger: self.logger)

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
                return self.makeRoleCredentialsResponse(accessKeyId: "AKIACONFIG")
            }

            let provider = SSOCredentialProvider(profileName: "dev", configPath: env.configPath!, httpClient: mockHTTPClient)
            let credential = try await provider.getCredential(logger: self.logger)
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
                return self.makeRoleCredentialsResponse(accessKeyId: "AKIALEGACYCFG")
            }

            let provider = SSOCredentialProvider(profileName: "legacy", configPath: env.configPath!, httpClient: mockHTTPClient)
            let credential = try await provider.getCredential(logger: self.logger)
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
                return self.makeRoleCredentialsResponse(accessKeyId: "AKIADEFAULT")
            }

            // No profileName = defaults to "default"
            let provider = SSOCredentialProvider(configPath: env.configPath!, httpClient: mockHTTPClient)
            let credential = try await provider.getCredential(logger: self.logger)
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
        try await withConfigFile(
            """
            [profile existing]
            sso_start_url = https://test.awsapps.com/start
            sso_region = us-east-1
            sso_account_id = 123456789012
            sso_role_name = TestRole
            """
        ) { configPath in
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
        try await withConfigFile(
            """
            [profile broken]
            sso_session = nonexistent-session
            sso_account_id = 123456789012
            sso_role_name = TestRole
            """
        ) { configPath in
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
        try await withConfigFile(
            """
            [profile incomplete]
            sso_session = my-sso
            sso_account_id = 123456789012
            sso_role_name = TestRole

            [sso-session my-sso]
            sso_region = us-east-1
            """
        ) { configPath in
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
        try await withConfigFile(
            """
            [profile partial]
            sso_start_url = https://test.awsapps.com/start
            sso_region = us-east-1
            sso_account_id = 123456789012
            """
        ) { configPath in
            let provider = SSOCredentialProvider(profileName: "partial", configPath: configPath, httpClient: MockAWSHTTPClient())

            await #expect {
                try await provider.getCredential(logger: self.logger)
            } throws: { error in
                (error as? AWSSSOCredentialError)?.code == "ssoConfigMissing"
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
                return self.makeRoleCredentialsResponse(accessKeyId: "AKIAVALID")
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
}
