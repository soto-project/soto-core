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

import Foundation
import NIO
import NIOConcurrencyHelpers

/// Protocol providing future holding a credential
protocol CredentialProvider {
    func getCredential() -> EventLoopFuture<Credential>
}

/// Provides credentials that don't change
struct StaticCredentialProvider: CredentialProvider {
    let credential: Credential
    let eventLoopGroup: EventLoopGroup

    init(credential: Credential,  eventLoopGroup: EventLoopGroup) {
        self.credential = credential
        self.eventLoopGroup = eventLoopGroup
    }

    func getCredential() -> EventLoopFuture<Credential> {
        return eventLoopGroup.next().makeSucceededFuture(credential)
    }
}

/// Provides credentials acquired from the metadata service. These expire and need updated occasionally
class MetaDataCredentialProvider: CredentialProvider {
    private(set) var credential: Credential
    private(set) var refreshingCredentialFuture: EventLoopFuture<Credential>?
    let httpClient: AWSHTTPClient
    let lock = Lock()

    init(httpClient: AWSHTTPClient) {
        self.credential = ExpiringCredential(accessKeyId: "", secretAccessKey: "", expiration: Date.init(timeIntervalSince1970: 0))
        self.refreshingCredentialFuture = nil
        self.httpClient = httpClient
    }
    
    func getCredential() -> EventLoopFuture<Credential> {
        lock.lock()
        let credential = self.credential
        lock.unlock()
        
        if let credential = credential as? ExpiringCredential, credential.nearExpiration() == false {
            return httpClient.eventLoopGroup.next().makeSucceededFuture(credential)
        }
        
        // we need to refresh the credentials
        return self.refreshCredentials()
    }
    
    func refreshCredentials() -> EventLoopFuture<Credential> {
        return lock.withLock {
        
            if let future = refreshingCredentialFuture {
                // a refresh is already running
                return future
            }
            
            let credentialFuture = MetaDataService.getCredential(httpClient: self.httpClient)
                .map { (credential)->Credential in
                    return self.lock.withLock {
                        self.credential = credential
                        self.refreshingCredentialFuture = nil
                        return credential
                    }
            }
            self.refreshingCredentialFuture = credentialFuture
            return credentialFuture
        }
    }
}
