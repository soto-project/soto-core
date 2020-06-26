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

public struct GroupCredentialProvider: CredentialProviderWrapper {
    
    let providers: [CredentialProviderWrapper]

    public init(_ providers: [CredentialProviderWrapper]? = nil) {
        #if os(Linux)
        self.providers = providers ?? [
            EnvironmentCredentialProvider(),
            ECSCredentialProvider(),
            EC2InstanceCredentialProvider(),
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
    
    public func getProvider(httpClient: AWSHTTPClient, on eventLoop: EventLoop) -> CredentialProvider {
        return Provider(providers: self.providers, httpClient: httpClient, on: eventLoop)
    }
    
    class Provider: CredentialProvider {
        let lock = Lock()
        var internalProvider: CredentialProvider? {
            get {
                self.lock.withLock {
                    _internalProvider
                }
            }
        }
        let providers: [CredentialProviderWrapper]
        let startupPromise: EventLoopPromise<CredentialProvider>

        private var _internalProvider: CredentialProvider? = nil
        
        init(providers: [CredentialProviderWrapper], httpClient: AWSHTTPClient, on eventLoop: EventLoop) {
            self.providers = providers
            self.startupPromise = eventLoop.makePromise(of: CredentialProvider.self)
            setupInternalProvider(httpClient: httpClient, on: eventLoop)
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
        
        private func setupInternalProvider(httpClient: AWSHTTPClient, on eventLoop: EventLoop) {
            func _setupInternalProvider(_ index: Int) {
                guard index < self.providers.count else {
                    startupPromise.fail(CredentialProviderError.noProvider)
                    return
                }
                let provider = self.providers[index].getProvider(httpClient: httpClient, on: eventLoop)
                provider.getCredential(on: eventLoop).whenComplete { result in
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
}
