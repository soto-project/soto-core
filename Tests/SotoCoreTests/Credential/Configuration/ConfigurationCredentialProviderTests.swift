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

#if ConfigurationSupport

import AsyncHTTPClient
import Configuration
import Logging
import SotoTestUtils
import Testing

@testable import SotoCore

@Suite("Configuration Credential Provider")
struct ConfigurationCredentialProviderTests {
    func makeContext() -> (CredentialProviderFactory.Context, HTTPClient) {
        let httpClient = HTTPClient(eventLoopGroupProvider: .singleton)
        return (.init(httpClient: httpClient, logger: TestEnvironment.logger, options: .init()), httpClient)
    }

    func reader(_ values: [AbsoluteConfigKey: ConfigValue]) -> ConfigReader {
        ConfigReader(provider: InMemoryProvider(values: values))
    }

    @Test("Static credentials with session token")
    func staticCredentialsWithSessionToken() async throws {
        let (context, httpClient) = makeContext()
        let factory: CredentialProviderFactory = .configuration(
            reader([
                "AWS_ACCESS_KEY_ID": "key",
                "AWS_SECRET_ACCESS_KEY": "secret",
                "AWS_SESSION_TOKEN": "token",
            ])
        )
        let provider = factory.createProvider(context: context)
        let credential = try await provider.getCredential(logger: TestEnvironment.logger)
        try await provider.shutdown()
        try await httpClient.shutdown()

        #expect(credential.accessKeyId == "key")
        #expect(credential.secretAccessKey == "secret")
        #expect(credential.sessionToken == "token")
    }

    @Test("Static credentials without session token")
    func staticCredentialsWithoutSessionToken() async throws {
        let (context, httpClient) = makeContext()
        let factory: CredentialProviderFactory = .configuration(
            reader([
                "AWS_ACCESS_KEY_ID": "key",
                "AWS_SECRET_ACCESS_KEY": "secret",
            ])
        )
        let provider = factory.createProvider(context: context)
        let credential = try await provider.getCredential(logger: TestEnvironment.logger)
        try await provider.shutdown()
        try await httpClient.shutdown()

        #expect(credential.accessKeyId == "key")
        #expect(credential.secretAccessKey == "secret")
        #expect(credential.sessionToken == nil)
    }

    @Test("Static credentials take precedence over web identity keys")
    func staticTakesPrecedence() async throws {
        let (context, httpClient) = makeContext()
        let factory: CredentialProviderFactory = .configuration(
            reader([
                "AWS_ACCESS_KEY_ID": "key",
                "AWS_SECRET_ACCESS_KEY": "secret",
                "AWS_ROLE_ARN": "arn:aws:iam::123456789012:role/test",
                "AWS_ROLE_SESSION_NAME": "session",
                "AWS_WEB_IDENTITY_TOKEN_FILE": "/tmp/token",
            ])
        )
        let provider = factory.createProvider(context: context)
        try await provider.shutdown()
        try await httpClient.shutdown()

        #expect(provider is StaticCredentialProvider)
    }

    @Test("Web identity keys resolve to a rotating STS provider")
    func webIdentityResolvesToRotatingProvider() async throws {
        let (context, httpClient) = makeContext()
        let factory: CredentialProviderFactory = .configuration(
            reader([
                "AWS_ROLE_ARN": "arn:aws:iam::123456789012:role/test",
                "AWS_ROLE_SESSION_NAME": "session",
                "AWS_WEB_IDENTITY_TOKEN_FILE": "/tmp/token",
                "AWS_REGION": "eu-west-1",
            ])
        )
        let provider = factory.createProvider(context: context)
        try await provider.shutdown()
        try await httpClient.shutdown()

        #expect(provider is RotatingCredentialProvider)
    }

    @Test("Container relative URI resolves to a rotating ECS provider")
    func ecsResolvesToRotatingProvider() async throws {
        let (context, httpClient) = makeContext()
        let factory: CredentialProviderFactory = .configuration(
            reader([
                "AWS_CONTAINER_CREDENTIALS_RELATIVE_URI": "/v2/credentials/abc"
            ])
        )
        let provider = factory.createProvider(context: context)
        try await provider.shutdown()
        try await httpClient.shutdown()

        #expect(provider is RotatingCredentialProvider)
    }

    @Test("No recognised keys resolve to a null provider")
    func emptyReaderResolvesToNullProvider() async throws {
        let (context, httpClient) = makeContext()
        let factory: CredentialProviderFactory = .configuration(reader([:]))
        let provider = factory.createProvider(context: context)
        try await provider.shutdown()
        try await httpClient.shutdown()

        #expect(provider is NullCredentialProvider)
    }
}

#endif  // ConfigurationSupport
