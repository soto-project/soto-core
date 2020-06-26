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

/// get credentials from a list of possible credential providers
class GroupCredentialProvider: CredentialProvider {
    /// the provider chosen to supply credentials
    var internalProvider: CredentialProvider? {
        get {
            self.lock.withLock {
                _internalProvider
            }
        }
    }
    /// promise to find a credential provider
    let startupPromise: EventLoopPromise<CredentialProvider>
    
    private let lock = Lock()
    private var _internalProvider: CredentialProvider? = nil

    init(providers: [CredentialProviderFactory]? = nil, context: CredentialProviderFactory.Context) {
        #if os(Linux)
        let providers = providers ?? [
            .environment,
            .ecs,
            .ec2
        ]
        #else
        let providers = providers ?? [
            .environment
        ]
        #endif
        self.startupPromise = context.eventLoop.makePromise(of: CredentialProvider.self)
        setupInternalProvider(providers: providers, context: context)
    }
    
    func syncShutdown() throws {
        _ = try startupPromise.futureResult.wait()
    }
    
    func getCredential(on eventLoop: EventLoop) -> EventLoopFuture<Credential> {
        if let provider = self.internalProvider {
            return provider.getCredential(on: eventLoop)
        }
        
        return self.startupPromise.futureResult.hop(to: eventLoop).flatMap { provider in
            return provider.getCredential(on: eventLoop)
        }
    }
    
    /// goes through list of providers. If provider is able to provide credentials then use that one, otherwise move onto the next
    /// provider in the list
    private func setupInternalProvider(providers: [CredentialProviderFactory], context: CredentialProviderFactory.Context) {
        func _setupInternalProvider(_ index: Int) {
            guard index < providers.count else {
                startupPromise.fail(CredentialProviderError.noProvider)
                return
            }
            let providerFactory = providers[index]
            let provider = providerFactory.createProvider(context: context)
            provider.getCredential(on: context.eventLoop).whenComplete { result in
                switch result {
                case .success:
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
