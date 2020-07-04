//===----------------------------------------------------------------------===//
//
// This source file is part of the AWSSDKSwift open source project
//
// Copyright (c) 2017-2020 the AWSSDKSwift project authors
// Licensed under Apache License v2.0
//
// See LICENSE.txt for license information
// See CONTRIBUTORS.txt for the list of AWSSDKSwift project authors
//
// SPDX-License-Identifier: Apache-2.0
//
//===----------------------------------------------------------------------===//

import NIO
import NIOConcurrencyHelpers
import struct Foundation.TimeInterval

/// The `RotatingCredentialProvider` shall be of help if you wish to implement your own provider
/// strategy. If your Credential conforms to the `ExpiringCredential` protocol, the `RotatingCredentialProvider`
/// checks whether your `credential` is still valid before every request.
/// If needed the `RotatingCrendentialProvider` requests a new credential from the provided `Client`.
public final class RotatingCredentialProvider: CredentialProvider {
    let remainingTokenLifetimeForUse: TimeInterval

    public  let provider        : CredentialProvider
    private let lock            = NIOConcurrencyHelpers.Lock()
    private var credential      : Credential? = nil
    private var credentialFuture: EventLoopFuture<Credential>? = nil

    public init(eventLoop: EventLoop, provider: CredentialProvider, remainingTokenLifetimeForUse: TimeInterval? = nil) {
        self.provider = provider
        self.remainingTokenLifetimeForUse = remainingTokenLifetimeForUse ?? 3 * 60
        _ = refreshCredentials(on: eventLoop)
    }

    public func syncShutdown() throws {
        let future: EventLoopFuture<Credential>? = self.lock.withLock { credentialFuture }
        if let future = future {
            _ = try future.wait()
        }
        try provider.syncShutdown()
    }

    public func getCredential(on eventLoop: EventLoop) -> EventLoopFuture<Credential> {
        self.lock.lock()
        let cred = credential
        self.lock.unlock()

        switch cred {
        case .none:
            return self.refreshCredentials(on: eventLoop)
        case .some(let cred as ExpiringCredential):
            if cred.isExpiring(within: remainingTokenLifetimeForUse) {
                // the credentials are expiring... let's refresh
                return self.refreshCredentials(on: eventLoop)
            }

            return eventLoop.makeSucceededFuture(cred)
        case .some(let cred):
            // we don't have expiring credentials
            return eventLoop.makeSucceededFuture(cred)
        }
    }

    private func refreshCredentials(on eventLoop: EventLoop) -> EventLoopFuture<Credential> {
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

        credentialFuture = self.provider.getCredential(on: eventLoop)
            .map { (credential) -> (Credential) in
                // update the internal credential locked
                self.lock.withLock {
                    self.credentialFuture = nil
                    self.credential = credential
                }
                return credential
            }

        return credentialFuture!
    }
}
