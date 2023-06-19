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

import struct Foundation.Date
import struct Foundation.TimeInterval
import Logging
import NIOConcurrencyHelpers
import NIOCore
import SotoSignerV4

/// Wrap a credential provider that returns an `ExpiringCredential`
///
/// Used for wrapping another credential provider whose `getCredential` method returns an `ExpiringCredential`.
/// If no credential is available, or the current credentials are going to expire in the near future  the wrapped credential provider
/// `getCredential` is called again. If current credentials have not expired they are returned otherwise we wait on new
/// credentials being provided.
public final class RotatingCredentialProvider: CredentialProvider {
    let expiringCredential: ExpiringValue<Credential>

    public let provider: CredentialProvider

    public init(context: CredentialProviderFactory.Context, provider: CredentialProvider, remainingTokenLifetimeForUse: TimeInterval? = nil) {
        self.provider = provider
        self.expiringCredential = .init(threshold: remainingTokenLifetimeForUse ?? 3 * 60) {
            try await Self.getCredentialAndExpiration(provider: provider, logger: context.logger)
        }
    }

    /// Shutdown credential provider
    public func shutdown() async throws {
        await expiringCredential.cancel()
        try await provider.shutdown()
    }

    public func getCredential(logger: Logger) async throws -> Credential {
        return try await expiringCredential.getValue {
            try await Self.getCredentialAndExpiration(provider: self.provider, logger: logger)
        }
    }

    static func getCredentialAndExpiration(provider: CredentialProvider, logger: Logger) async throws -> (Credential, Date) {
        logger.debug("Refeshing AWS credentials", metadata: ["aws-credential-provider": .string("\(self)")])
        try Task.checkCancellation()
        let credential = try await provider.getCredential(logger: logger)
        logger.debug("AWS credentials ready", metadata: ["aws-credential-provider": .string("\(self)")])
        if let expiringCredential = credential as? ExpiringCredential {
            return (expiringCredential, expiringCredential.expiration)
        } else {
            return (credential, Date.distantFuture)
        }
    }
}

extension RotatingCredentialProvider: CustomStringConvertible {
    public var description: String { return "\(type(of: self))(\(provider.description))" }
}
