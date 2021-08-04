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

/// get credentials from a list of possible credential providers. Goes through list of providers from start to end
/// attempting to get credentials. Once it finds a `CredentialProvider` that supplies credentials use that
/// one
class RuntimeSelectorCredentialProvider: CredentialProviderSelector {
    /// promise to find a credential provider
    let startupPromise: EventLoopPromise<CredentialProvider>
    let lock = Lock()
    var _internalProvider: CredentialProvider?

    init(providers: [CredentialProviderFactory], context: CredentialProviderFactory.Context) {
        self.startupPromise = context.eventLoop.makePromise(of: CredentialProvider.self)
        self.startupPromise.futureResult.whenSuccess { result in
            self.internalProvider = result
        }
        self.setupInternalProvider(providers: providers, context: context)
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
            provider.getCredential(on: context.eventLoop, context: context.context).whenComplete { result in
                switch result {
                case .success:
                    context.context.logger.debug("Select credential provider", metadata: ["aws-credential-provider": .string("\(provider)")])
                    self.startupPromise.succeed(provider)
                case .failure:
                    context.context.logger.log(level: context.options.errorLogLevel, "Select credential provider failed")
                    _setupInternalProvider(index + 1)
                }
            }
        }

        _setupInternalProvider(0)
    }
}
