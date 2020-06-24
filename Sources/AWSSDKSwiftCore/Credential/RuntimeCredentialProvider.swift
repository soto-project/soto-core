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

class RuntimeCredentialProvider: CredentialProvider {
    
    static func createProvider(
        on eventLoop: EventLoop,
        httpClient: AWSHTTPClient) -> CredentialProvider
    {
        // 1. has the environment credentials? let's use those...
        //    we are creating static environment credentials here to save the lock in runtime
        //    credential scenarios.
        if let credential = StaticCredential.fromEnvironment() {
            return credential
        }
        
        // 2. we don't have static credentials. let's determine what to do while running
        return RuntimeCredentialProvider(eventLoop: eventLoop, httpClient: httpClient)
    }
    
    let lock = Lock()
    var internalProvider: CredentialProvider? {
        get {
            self.lock.withLock {
                _internalProvider
            }
        }
    }
    let startupPromise: EventLoopPromise<Void>
    
    private var _internalProvider: CredentialProvider? = nil
    
    init(eventLoop: EventLoop, httpClient: AWSHTTPClient) {
        self.startupPromise = eventLoop.makePromise(of: Void.self)
        self.createInternalProvider(on: eventLoop, httpClient: httpClient)
    }
    
    func syncShutdown() throws {
        try startupPromise.futureResult.wait()
    }
    
    func getCredential(on eventLoop: EventLoop) -> EventLoopFuture<Credential> {
        if let provider = self.internalProvider {
            return provider.getCredential(on: eventLoop)
        }
        
        return self.startupPromise.futureResult.hop(to: eventLoop).flatMap { _ in
            guard let provider = self.internalProvider else {
                preconditionFailure("Expected to have a credential provider after startup")
            }
            
            return provider.getCredential(on: eventLoop)
        }
    }
    
    private struct NoProviderYetError: Error {
        
    }

    private func createInternalProvider(on eventLoop: EventLoop, httpClient: AWSHTTPClient) {
        // we walk down the chain as long we haven't created a valid `CredentialProvider`
        // we don't check for static or environment credentials here again, those should have been
        // created in `static createProvider()` above.
        var future: EventLoopFuture<CredentialProvider> = eventLoop.makeFailedFuture(NoProviderYetError())
        #if os(Linux)
            // 3. if we are on linux is an ECSMetaData endpoint in the environment. Do we reach the ECSMetaDataService?
            future = future.flatMapError { (error) -> EventLoopFuture<CredentialProvider> in
                let ecsMetaDataClient = ECSMetaDataClient(httpClient: httpClient)
                let credentialProvider = RotatingCredentialProvider(client: ecsMetaDataClient)
                return credentialProvider.getCredential(on: eventLoop).map { _ in
                    // first refresh has been successful. we could access meta data!
                    return credentialProvider
                }
            }
            // 4. if we are on linux can we access the ec2 meta data service?
            .flatMapError { (error) -> EventLoopFuture<CredentialProvider> in
                let ec2MetaDataClient = InstanceMetaDataClient(httpClient: httpClient)
                let credentialProvider = RotatingCredentialProvider(client: ec2MetaDataClient)
                return credentialProvider.getCredential(on: eventLoop).map { _ in
                    // first refresh has been successful. we could access meta data, let's use this credential provider
                    return credentialProvider
                }
            }
        #endif
        
        // 5. can we find credentials in the aws cli config file? If yes, let's use those
        future.flatMapError { (error) -> EventLoopFuture<CredentialProvider> in
                let profile = Environment["AWS_PROFILE"] ?? "default"
                return StaticCredential.fromSharedCredentials(credentialsFilePath: "~/.aws/credentials", profile: profile, on: eventLoop).map { $0 }
            }
            // 6. if we haven't found something yet, we will not be able to sign. Create empty static credentials
            .flatMapErrorThrowing { (_) -> CredentialProvider in
                return StaticCredential(accessKeyId: "", secretAccessKey: "")
            }
            .whenComplete { (result) in
                guard case .success(let provider) = result else {
                    preconditionFailure("Did not expect to not have a credential provider at this point")
                }
                
                self.lock.withLockVoid {
                    self._internalProvider = provider
                }
                
                self.startupPromise.succeed(())
            }
    }    
}
