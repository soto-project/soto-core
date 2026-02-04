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

import AsyncHTTPClient
import Logging
import NIOConcurrencyHelpers
import NIOCore
import NIOPosix
import SotoSignerV4

/// Provides AWS credentials
public protocol CredentialProvider: Sendable, CustomStringConvertible {
    /// Return credential
    /// - Parameters:
    ///   - logger: Logger to use
    func getCredential(logger: Logger) async throws -> Credential

    /// Shutdown credential provider
    func shutdown() async throws
}

extension CredentialProvider {
    public func shutdown() async throws {}

    public var description: String { "\(type(of: self))" }
}

/// Provides factory functions for `CredentialProvider`s.
///
/// The factory functions are only called once the `AWSClient` has been setup. This means we can supply
/// things like a `Logger` and `HTTPClient` to the credential provider when we construct it.
public struct CredentialProviderFactory: Sendable {
    /// The initialization context for a `ContextProvider`
    public struct Context: Sendable {
        /// The `AWSClient`s internal `HTTPClient`
        public let httpClient: AWSHTTPClient
        /// The `Logger` attached to the AWSClient
        public let logger: Logger
        /// AWSClient options
        public let options: AWSClient.Options
    }

    private let cb: @Sendable (Context) -> CredentialProvider

    private init(cb: @escaping @Sendable (Context) -> CredentialProvider) {
        self.cb = cb
    }

    internal func createProvider(context: Context) -> CredentialProvider {
        self.cb(context)
    }
}

extension CredentialProviderFactory {
    /// The default CredentialProvider used to access credentials
    ///
    /// If running on Linux this will look for credentials in the environment,
    /// ECS environment variables, EC2 metadata endpoint and finally the AWS config
    /// files. On macOS is looks in the environment and then the config file.
    public static var `default`: CredentialProviderFactory {
        #if os(Linux)
        return .selector(.environment, .ecs, .ec2, .configFile(), .login())
        #else
        if #available(macOS 11.0, iOS 14.0, tvOS 14.0, watchOS 7.0, *) {
            return .selector(.environment, .configFile(), .login())
        } else {
            return .selector(.environment, .configFile())
        }
        #endif
    }

    /// Create a custom `CredentialProvider`
    public static func custom(_ factory: @escaping @Sendable (Context) -> CredentialProvider) -> CredentialProviderFactory {
        Self(cb: factory)
    }

    /// Get `CredentialProvider` details from the environment
    /// Looks in environment variables `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY` and `AWS_SESSION_TOKEN`
    /// and then checks `AWS_ROLE_ARN`, `AWS_ROLE_SESSION_NAME` and `AWS_WEB_IDENTITY_TOKEN_FILE`.
    public static var environment: CredentialProviderFactory {
        .environment()
    }

    /// Get `CredentialProvider` details from the environment
    /// Looks in environment variables `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY` and `AWS_SESSION_TOKEN`
    /// and then checks `AWS_ROLE_ARN`, `AWS_ROLE_SESSION_NAME` and `AWS_WEB_IDENTITY_TOKEN_FILE`.
    public static func environment(endpoint: String? = nil, threadPool: NIOThreadPool = .singleton) -> CredentialProviderFactory {
        Self { context -> CredentialProvider in
            StaticCredential.fromEnvironment()
                ?? STSAssumeRoleCredentialProvider.fromEnvironment(
                    context: context,
                    endpoint: endpoint,
                    threadPool: threadPool
                )
                ?? NullCredentialProvider()
        }
    }

    /// Return static credentials.
    public static func `static`(accessKeyId: String, secretAccessKey: String, sessionToken: String? = nil) -> CredentialProviderFactory {
        Self { _ in
            StaticCredential(
                accessKeyId: accessKeyId,
                secretAccessKey: secretAccessKey,
                sessionToken: sessionToken
            )
        }
    }

    /// Use credentials supplied via the ECS Metadata endpoint
    public static var ecs: CredentialProviderFactory {
        Self { context in
            if let provider = ECSMetaDataClient(httpClient: context.httpClient) {
                return RotatingCredentialProvider(context: context, provider: provider)
            }

            // fallback
            return NullCredentialProvider()
        }
    }

    /// Use credentials supplied via the EC2 Instance Metadata endpoint
    public static var ec2: CredentialProviderFactory {
        Self { context in
            let provider = InstanceMetaDataClient(httpClient: context.httpClient)
            return RotatingCredentialProvider(context: context, provider: provider)
        }
    }

    /// Use credentials loaded from your AWS config
    ///
    /// Uses AWS cli credentials and optional profile configuration files, normally located at
    ///  `~/.aws/credentials` and `~/.aws/config`.
    public static func configFile(
        credentialsFilePath: String? = nil,
        configFilePath: String? = nil,
        profile: String? = nil
    ) -> CredentialProviderFactory {
        Self { context in
            let provider = ConfigFileCredentialProvider(
                credentialsFilePath: credentialsFilePath ?? ConfigFileLoader.defaultCredentialsPath,
                configFilePath: configFilePath ?? ConfigFileLoader.defaultProfileConfigPath,
                profile: profile,
                context: context
            )
            return RotatingCredentialProvider(context: context, provider: provider)
        }
    }

    /// Return credential provider for AWS_ROLE_ARN, AWS_ROLE_SESSION_NAME,
    /// AWS_WEB_IDENTITY_TOKEN_FILE environment variables
    public static func stsRoleARN(
        credentialProvider: CredentialProviderFactory
    ) -> CredentialProviderFactory {
        Self { context in
            guard let provider = STSAssumeRoleCredentialProvider.fromEnvironment(context: context) else {
                return NullCredentialProvider()
            }
            return RotatingCredentialProvider(context: context, provider: provider)
        }
    }

    /// Don't supply any credentials
    public static var empty: CredentialProviderFactory {
        Self { _ in
            EmptyCredential()
        }
    }

    /// Use the list of credential providers supplied to get credentials.
    ///
    /// When searching for credentials it will go through the list sequentially and the first credential
    /// provider that returns valid credentials will be used.
    public static func selector(_ providers: CredentialProviderFactory...) -> CredentialProviderFactory {
        Self { context in
            if providers.count == 1 {
                return providers[0].createProvider(context: context)
            } else {
                return RuntimeSelectorCredentialProvider(providers: providers, context: context)
            }
        }
    }
}
