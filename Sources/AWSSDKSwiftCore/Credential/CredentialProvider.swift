//
//  CredentialProvider.swift
//  AWSSDKSwift
//
//  Created by Adam Fowler on 2019/12/5
//
//
import AWSSigner
import Foundation
import NIO

/// Protocol providing future holding a credential
protocol CredentialProvider {
    mutating func getCredential() -> EventLoopFuture<Credential>
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
    var credentialFuture: EventLoopFuture<Credential>
    let httpClient: AWSHTTPClient
    let lock = NSLock()

    init(httpClient: AWSHTTPClient) {
        let credential = ExpiringCredential(accessKeyId: "", secretAccessKey: "", expiration: Date.init(timeIntervalSince1970: 0))
        self.credentialFuture = httpClient.eventLoopGroup.next().makeSucceededFuture(credential)
        self.httpClient = httpClient
    }
    
    func getCredential() -> EventLoopFuture<Credential> {
        return credentialFuture.flatMap { credential in
            if let expiringCredential = credential as? ExpiringCredential, expiringCredential.nearExpiration() {
                return self.refresh()
            } else {
                return self.credentialFuture
            }
        }
    }
    
    func refresh() -> EventLoopFuture<Credential> {
        let future = MetaDataService.getCredential(httpClient: self.httpClient)
        lock.lock()
        self.credentialFuture = future
        lock.unlock()
        return self.credentialFuture
    }
}
