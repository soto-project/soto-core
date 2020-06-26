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
import AWSSignerV4
import NIOConcurrencyHelpers

/// Protocol providing future holding a credential
public protocol CredentialProvider {
    func getCredential(on eventLoop: EventLoop) -> EventLoopFuture<Credential>
    func syncShutdown() throws
}

extension CredentialProvider {
    public func syncShutdown() throws {
        return
    }
}

/// A helper struct to defer the creation of a `CredentialProvider` until after the AWSClient has been created.
public struct CredentialProviderFactory {
    
    /// The initialization context for a `ContextProvider`
    public struct Context {
        /// The `AWSClient`s internal `HTTPClient`
        let httpClient: AWSHTTPClient
        /// The `EventLoop` that the `CredentialProvider` should use for credential refreshs
        let eventLoop: EventLoop
    }
    
    private let cb: (Context) -> CredentialProvider
    
    private init(cb: @escaping (Context) -> CredentialProvider) {
        self.cb = cb
    }
    
    internal func createProvider(context: Context) -> CredentialProvider {
        self.cb(context)
    }
}

extension CredentialProviderFactory {
    
    /// Use this method to initialize your custom `CredentialProvider`
    public static func custom(_ factory: @escaping (Context) -> CredentialProvider) -> CredentialProviderFactory {
        Self(cb: factory)
    }
    
    /// Use this method to enforce the use of a `CredentialProvider` that uses the environment variables `AWS_ACCESS_KEY_ID` and `AWS_SECRET_ACCESS_KEY` to create the credentials.
    public static var environment: CredentialProviderFactory {
        Self() { _ -> CredentialProvider in
            return StaticCredential.fromEnvironment() ?? NullCredentialProvider()
        }
    }
    
    /// Use this method to enforce the use of a `CredentialProvider` that uses static credentials.
    public static func `static`(accessKeyId: String, secretAccessKey: String, sessionToken: String? = nil) -> CredentialProviderFactory {
        Self() { _ in
            StaticCredential(
                accessKeyId: accessKeyId,
                secretAccessKey: secretAccessKey,
                sessionToken: sessionToken
            )
        }
    }

    /// Use this method to enforce the usage of the Credentials supplied via the ECS Metadata endpoint
    public static var ecs: CredentialProviderFactory {
        Self() { context in
            if let client = ECSMetaDataClient(httpClient: context.httpClient) {
                return RotatingCredentialProvider(eventLoop: context.eventLoop, client: client)
            }
            
            // fallback
            return NullCredentialProvider()
        }
    }
    
    /// Use this method to enforce the usage of the Credentials supplied via the EC2 Instance Metadata endpoint
    public static var ec2: CredentialProviderFactory {
        Self() { context in
            let client = InstanceMetaDataClient(httpClient: context.httpClient)
            return RotatingCredentialProvider(eventLoop: context.eventLoop, client: client)
        }
    }
    
    /// Use this method to let the runtime determine which `Credentials` to use
    public static var runtime: CredentialProviderFactory {
        Self() { context in
            RuntimeCredentialProvider.createProvider(
                on: context.eventLoop,
                httpClient: context.httpClient)
        }
    }
    
    /// Use this method to load credentials from your aws cli credential file, normally located at `~/.aws/credentials`
    public static func configFile(credentialsFilePath: String = "~/.aws/credentials", profile: String? = nil) -> CredentialProviderFactory {
        let profile = profile ?? Environment["AWS_PROFILE"] ?? "default"
        return Self() { context in
            DeferredCredentialProvider(context: context) { (context) -> EventLoopFuture<CredentialProvider> in
                return StaticCredential.fromSharedCredentials(
                    credentialsFilePath: credentialsFilePath,
                    profile: profile,
                    on: context.eventLoop).map { $0 }
            }
        }
    }
    
    /// Enforce the use of no credentials.
    public static var empty: CredentialProviderFactory {
        Self() { context in
            StaticCredential(accessKeyId: "", secretAccessKey: "")
        }
    }
}

private class DeferredCredentialProvider: CredentialProvider {
    
    let lock = Lock()
    var internalProvider: CredentialProvider? {
        get {
            self.lock.withLock {
                _internalProvider
            }
        }
    }

    private var startupPromise: EventLoopPromise<CredentialProvider>
    private var _internalProvider: CredentialProvider? = nil

    init(context: CredentialProviderFactory.Context, cb: @escaping (CredentialProviderFactory.Context) -> EventLoopFuture<CredentialProvider>) {
        
        self.startupPromise = context.eventLoop.makePromise(of: CredentialProvider.self)
        self.startupPromise.futureResult.whenComplete { result in
            self.lock.withLock { () in
                switch result {
                case .success(let provider):
                    self._internalProvider = provider
                case .failure(_):
                    self._internalProvider = NullCredentialProvider()
                }
            }
        }
        
        cb(context).cascade(to: self.startupPromise)
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
}
