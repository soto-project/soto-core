//===----------------------------------------------------------------------===//
//
// This source file is part of the Soto for AWS open source project
//
// Copyright (c) 2017-2020 the Soto project authors
// Licensed under Apache License v2.0
//
// See LICENSE.txt for license information
// See CONTRIBUTORS.txt for the list of Soto project authors
//
// SPDX-License-Identifier: Apache-2.0
//
//===----------------------------------------------------------------------===//

import Baggage
import NIO
import NIOConcurrencyHelpers
import SotoSignerV4

/// Protocol for CredentialProvider that uses an internal CredentialProvider
///
/// When conforming to this protocol once you ahve the internal provider it should be supplying to
/// the startupPromise and you should set `internalProvider` when the setupPromise
/// result is available.
/// ```
/// init(providers: [CredentialProviderFactory], context: CredentialProviderFactory.Context) {
///    self.startupPromise = context.eventLoop.makePromise(of: CredentialProvider.self)
///    self.startupPromise.futureResult.whenSuccess { result in
///        self.internalProvider = result
///    }
///    self.setupInternalProvider(providers: providers, context: context)
/// }
/// ```
protocol CredentialProviderSelector: CredentialProvider, AnyObject {
    /// promise to find a credential provider
    var startupPromise: EventLoopPromise<CredentialProvider> { get }
    var lock: Lock { get }
    var _internalProvider: CredentialProvider? { get set }
}

extension CredentialProviderSelector {
    /// the provider chosen to supply credentials
    var internalProvider: CredentialProvider? {
        get {
            self.lock.withLock {
                _internalProvider
            }
        }
        set {
            self.lock.withLock {
                _internalProvider = newValue
            }
        }
    }

    func shutdown(on eventLoop: EventLoop) -> EventLoopFuture<Void> {
        return self.startupPromise.futureResult.flatMap { provider in
            provider.shutdown(on: eventLoop)
        }.hop(to: eventLoop)
    }

    func getCredential(on eventLoop: EventLoop, context: LoggingContext) -> EventLoopFuture<Credential> {
        if let provider = internalProvider {
            return provider.getCredential(on: eventLoop, context: context)
        }

        return self.startupPromise.futureResult.hop(to: eventLoop).flatMap { provider in
            return provider.getCredential(on: eventLoop, context: context)
        }
    }
}
