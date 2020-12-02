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

import Logging
import NIO
import NIOConcurrencyHelpers
import SotoSignerV4

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

    func shudown(on eventLoop: EventLoop) -> EventLoopFuture<Void> {
        return self.startupPromise.futureResult.flatMap { provider in
            provider.shutdown(on: eventLoop)
        }.hop(to: eventLoop)
    }

    func getCredential(on eventLoop: EventLoop, logger: Logger) -> EventLoopFuture<Credential> {
        if let provider = internalProvider {
            return provider.getCredential(on: eventLoop, logger: logger)
        }

        return self.startupPromise.futureResult.hop(to: eventLoop).flatMap { provider in
            return provider.getCredential(on: eventLoop, logger: logger)
        }
    }
}
