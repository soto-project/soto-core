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

class GroupCredentialProvider: CredentialProvider {
    
    let lock = Lock()
    var internalProvider: CredentialProvider? {
        get {
            self.lock.withLock {
                _internalProvider
            }
        }
    }
    var providers: [CredentialProvider]
    var startupPromise: EventLoopPromise<CredentialProvider>! = nil

    private var _internalProvider: CredentialProvider? = nil
    
    init(_ providers: [CredentialProvider]? = nil) {
        #if os(Linux)
        self.providers = providers ?? [
            EnvironmentCredentialProvider(),
            RotatingCredentialProvider(provider: ECSMetaDataClient()),
            RotatingCredentialProvider(provider: InstanceMetaDataClient()),
            ConfigFileCredentialProvider(),
            EmptyCredentialProvider()
        ]
        #else
        self.providers = providers ?? [
            EnvironmentCredentialProvider(),
            ConfigFileCredentialProvider(),
            EmptyCredentialProvider()
        ]
        #endif
    }
    
    func syncShutdown() throws {
        _ = try startupPromise?.futureResult.wait()
    }
    
    func setup(with client: AWSClient) -> Bool {
        let eventLoop = client.eventLoopGroup.next()
        self.startupPromise = eventLoop.makePromise(of: CredentialProvider.self)
        setupInternalProvider(on: eventLoop, with: client)
        return true
    }
    
    func getCredential(on eventLoop: EventLoop) -> EventLoopFuture<Credential> {
        if let provider = self.internalProvider {
            return provider.getCredential(on: eventLoop)
        }
        
        return self.startupPromise.futureResult.hop(to: eventLoop).flatMap { provider in
            return provider.getCredential(on: eventLoop)
        }
    }
    
    private func setupInternalProvider(on eventLoop: EventLoop, with client: AWSClient) {
        func _setupInternalProvider(_ index: Int) {
            guard index < self.providers.count else {
                startupPromise?.fail(CredentialProviderError.noProvider)
                return
            }
            let provider = self.providers[index]
            if provider.setup(with: client) {
                provider.getCredential(on: eventLoop).whenComplete { result in
                    switch result {
                    case .success:
                        self._internalProvider = provider
                        self.startupPromise?.succeed(provider)
                    case .failure:
                        _setupInternalProvider(index + 1)
                    }
                }
            } else {
                _setupInternalProvider(index + 1)
            }
        }
        
        _setupInternalProvider(0)
    }
}
