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

/// get credentials from a list of possible credential providers. Goes through list of providers from start to end
/// attempting to get credentials. Once it finds a `CredentialProvider` that supplies credentials use that
/// one
class RuntimeSelectorCredentialProvider: CredentialProvider {
    /// the provider chosen to supply credentials
    var internalProvider: CredentialProvider? {
        self.lock.withLock {
            _internalProvider
        }
    }

    /// promise to find a credential provider
    let startupPromise: EventLoopPromise<CredentialProvider>

    private let lock = Lock()
    private var _internalProvider: CredentialProvider?

    init(providers: [CredentialProviderFactory], context: CredentialProviderFactory.Context) {
        self.startupPromise = context.eventLoop.makePromise(of: CredentialProvider.self)
        self.setupInternalProvider(providers: providers, context: context)
    }

    func shudown(on eventLoop: EventLoop) -> EventLoopFuture<Void> {
        return self.startupPromise.futureResult.map { _ in }.hop(to: eventLoop)
    }

    func getCredential(on eventLoop: EventLoop, logger: Logger) -> EventLoopFuture<Credential> {
        if let provider = internalProvider {
            return provider.getCredential(on: eventLoop, logger: logger)
        }

        return self.startupPromise.futureResult.hop(to: eventLoop).flatMap { provider in
            return provider.getCredential(on: eventLoop, logger: logger)
        }
    }

    /// goes through list of providers. If provider is able to provide credentials then use that one, otherwise move onto the next
    /// provider in the list
    private func setupInternalProvider(providers: [CredentialProviderFactory], context: CredentialProviderFactory.Context) {
        func _setupInternalProvider(_ index: Int) {
            guard index < providers.count else {
                self.startupPromise.fail(CredentialProviderError.noProvider)
                return
            }
            let providerFactory = providers[index]
            let provider = providerFactory.createProvider(context: context)
            provider.getCredential(on: context.eventLoop, logger: context.logger).whenComplete { result in
                switch result {
                case .success:
                    context.logger.info("Select credential provider", metadata: ["aws-credential-provider": .string("\(provider)")])
                    self._internalProvider = provider
                    self.startupPromise.succeed(provider)
                case .failure:
                    _setupInternalProvider(index + 1)
                }
            }
        }

        _setupInternalProvider(0)
    }
}
