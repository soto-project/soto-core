//===----------------------------------------------------------------------===//
//
// This source file is part of the Soto for AWS open source project
//
// Copyright (c) 2017-2022 the Soto project authors
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
import SotoSignerV4

/// Provides AWS credentials
public protocol CredentialProvider: Sendable, CustomStringConvertible {
    /// Return credential
    /// - Parameters:
    ///   - eventLoop: EventLoop to run on
    ///   - logger: Logger to use
    func getCredential(logger: Logger) async throws -> Credential

    /// Shutdown credential provider
    /// - Parameter eventLoop: EventLoop to use when shutiting down
    func shutdown() async throws
}

extension CredentialProvider {
    public func shutdown() async throws {}

    public var description: String { return "\(type(of: self))" }
}

/// Provides factory functions for `CredentialProvider`s.
///
/// The factory functions are only called once the `AWSClient` has been setup. This means we can supply
/// things like a `Logger`, `EventLoop` and `HTTPClient` to the credential provider when we construct it.
public struct CredentialProviderFactory {
    /// The initialization context for a `ContextProvider`
    public struct Context {
        /// The `AWSClient`s internal `HTTPClient`
        public let httpClient: HTTPClient
        /// The `EventLoop` that the `CredentialProvider` should use for credential refreshs
        public let eventLoop: EventLoop
        /// The `Logger` attached to the AWSClient
        public let logger: Logger
        /// AWSClient options
        public let options: AWSClient.Options
    }

    private let cb: (Context) -> CredentialProvider

    private init(cb: @escaping (Context) -> CredentialProvider) {
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
        return .selector(.environment, .ecs, .ec2, .configFile())
        #else
        return .selector(.environment, .configFile())
        #endif
    }

    /// Create a custom `CredentialProvider`
    public static func custom(_ factory: @escaping (Context) -> CredentialProvider) -> CredentialProviderFactory {
        Self(cb: factory)
    }

    /// Get `CredentialProvider` details from the environment
    /// Looks in environment variables `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY` and `AWS_SESSION_TOKEN`.
    public static var environment: CredentialProviderFactory {
        Self { _ -> CredentialProvider in
            return StaticCredential.fromEnvironment() ?? NullCredentialProvider()
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
        return Self { context in
            let provider = ConfigFileCredentialProvider(
                credentialsFilePath: credentialsFilePath ?? ConfigFileLoader.defaultCredentialsPath,
                configFilePath: configFilePath ?? ConfigFileLoader.defaultProfileConfigPath,
                profile: profile,
                context: context
            )
            return RotatingCredentialProvider(context: context, provider: provider)
        }
    }

    /// Don't supply any credentials
    public static var empty: CredentialProviderFactory {
        Self { _ in
            StaticCredential(accessKeyId: "", secretAccessKey: "")
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
