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
    let remainingTokenLifetimeForUse: TimeInterval

    public let provider: CredentialProvider
    private let lock = NIOConcurrencyHelpers.NIOLock()
    private var credential: Credential?
    private var credentialFuture: EventLoopFuture<Credential>?

    public init(context: CredentialProviderFactory.Context, provider: CredentialProvider, remainingTokenLifetimeForUse: TimeInterval? = nil) {
        self.provider = provider
        self.remainingTokenLifetimeForUse = remainingTokenLifetimeForUse ?? 3 * 60
        _ = refreshCredentials(on: context.eventLoop, logger: context.logger)
    }

    /// Shutdown credential provider
    public func shutdown(on eventLoop: EventLoop) -> EventLoopFuture<Void> {
        return self.lock.withLock {
            if let future = credentialFuture {
                return future.and(provider.shutdown(on: eventLoop)).map { _ in }.hop(to: eventLoop)
            }
            return provider.shutdown(on: eventLoop)
        }
    }

    public func getCredential(on eventLoop: EventLoop, logger: Logger) -> EventLoopFuture<Credential> {
        self.lock.lock()
        let cred = credential
        self.lock.unlock()

        switch cred {
        case .none:
            return self.refreshCredentials(on: eventLoop, logger: logger)
        case .some(let cred as ExpiringCredential):
            if cred.isExpiring(within: remainingTokenLifetimeForUse) {
                // the credentials are expiring... let's refresh
                return self.refreshCredentials(on: eventLoop, logger: logger)
            }

            return eventLoop.makeSucceededFuture(cred)
        case .some(let cred):
            // we don't have expiring credentials
            return eventLoop.makeSucceededFuture(cred)
        }
    }

    private func refreshCredentials(on eventLoop: EventLoop, logger: Logger) -> EventLoopFuture<Credential> {
        self.lock.lock()
        defer { self.lock.unlock() }

        if let future = credentialFuture {
            // a refresh is already running
            if future.eventLoop !== eventLoop {
                // We want to hop back to the event loop we came in case
                // the refresh is resolved on another EventLoop.
                return future.hop(to: eventLoop)
            }
            return future
        }

        logger.debug("Refeshing AWS credentials", metadata: ["aws-credential-provider": .string("\(self)")])

        credentialFuture = self.provider.getCredential(on: eventLoop, logger: logger)
            .map { credential -> (Credential) in
                // update the internal credential locked
                self.lock.withLock {
                    self.credentialFuture = nil
                    self.credential = credential
                    logger.debug("AWS credentials ready", metadata: ["aws-credential-provider": .string("\(self)")])
                }
                return credential
            }

        return credentialFuture!
    }
}

extension RotatingCredentialProvider: CustomStringConvertible {
    public var description: String { return "\(type(of: self))(\(provider.description))" }
}

#if compiler(>=5.6)
// can use @unchecked Sendable here as access is protected by 'NIOLock'
extension RotatingCredentialProvider: @unchecked Sendable {}
#endif
