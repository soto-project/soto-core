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

import Logging
import NIOConcurrencyHelpers
import NIOCore
import SotoSignerV4

import struct Foundation.Date
import struct Foundation.TimeInterval

/// Wrap a credential provider that returns an `ExpiringCredential`
///
/// Used for wrapping another credential provider whose `getCredential` method returns an `ExpiringCredential`.
/// If no credential is available, or the current credentials are going to expire in the near future  the wrapped credential provider
/// `getCredential` is called again. If current credentials have not expired (within a threshold) they are returned otherwise we wait on new
/// credentials being provided.
public final class RotatingCredentialProvider: CredentialProvider {
    let expiringCredential: ExpiringValue<Credential>
    let validCredentialThreshold: TimeInterval
    public let provider: CredentialProvider

    ///  Initialize RotatingCredentialProvider
    /// - Parameters:
    ///   - context: Context used to create this credential provider
    ///   - provider: Credential provider to request credentials from
    ///   - remainingTokenLifetimeForUse: How near to expiration, before we request new credentials
    public init(
        context: CredentialProviderFactory.Context,
        provider: CredentialProvider,
        remainingTokenLifetimeForUse: TimeInterval? = nil
    ) {
        self.provider = provider
        self.validCredentialThreshold = 15
        self.expiringCredential = .init(threshold: remainingTokenLifetimeForUse ?? 165) {
            try await Self.getCredentialAndExpiration(provider: provider, validCredentialThreshold: 15, logger: context.logger)
        }
    }

    ///  Initialize RotatingCredentialProvider
    /// - Parameters:
    ///   - context: Context used to create this credential provider
    ///   - provider: Credential provider to request credentials from
    ///   - remainingTokenLifetimeForUse: How near to expiration, before we request new credentials
    ///   - validCredentialThreshold: How near to expiration do we return the current credentials
    public init(
        context: CredentialProviderFactory.Context,
        provider: CredentialProvider,
        remainingTokenLifetimeForUse: TimeInterval? = nil,
        validCredentialThreshold: TimeInterval
    ) {
        self.provider = provider
        self.validCredentialThreshold = validCredentialThreshold
        self.expiringCredential = .init(threshold: remainingTokenLifetimeForUse ?? 3 * 60) {
            try await Self.getCredentialAndExpiration(provider: provider, validCredentialThreshold: validCredentialThreshold, logger: context.logger)
        }
    }

    /// Shutdown credential provider
    public func shutdown() async throws {
        await self.expiringCredential.cancel()
        // ensure internal credential provider is not still running
        _ = try? await self.expiringCredential.getValue {
            try Task.checkCancellation()
            preconditionFailure("Cannot get here")
        }
        try await self.provider.shutdown()
    }

    public func getCredential(logger: Logger) async throws -> Credential {
        try await self.expiringCredential.getValue {
            try await Self.getCredentialAndExpiration(
                provider: self.provider,
                validCredentialThreshold: self.validCredentialThreshold,
                logger: logger
            )
        }
    }

    static func getCredentialAndExpiration(
        provider: CredentialProvider,
        validCredentialThreshold: TimeInterval,
        logger: Logger
    ) async throws -> (Credential, Date) {
        logger.debug(
            "Refeshing AWS credentials",
            metadata: ["aws-credential-provider": .string("\(self)(\(provider.description))")]
        )
        try Task.checkCancellation()
        let credential = try await provider.getCredential(logger: logger)
        logger.debug(
            "AWS credentials ready",
            metadata: ["aws-credential-provider": .string("\(self)(\(provider.description))")]
        )
        if let expiringCredential = credential as? ExpiringCredential {
            return (
                expiringCredential,
                expiringCredential.expiration.addingTimeInterval(-validCredentialThreshold)
            )
        } else {
            return (credential, Date.distantFuture)
        }
    }
}

extension RotatingCredentialProvider: CustomStringConvertible {
    public var description: String { "\(type(of: self))(\(self.provider.description))" }
}
