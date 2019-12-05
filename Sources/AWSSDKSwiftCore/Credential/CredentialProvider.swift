//
//  Credential.swift
//  AWSSDKSwiftCore
//
//  Created by Yuki Takei on 2017/04/05.
//
//

import NIO
import AWSSigner

/// Protocol for providing credential details for accessing AWS services
public protocol CredentialProvider {
    func getCredential() -> EventLoopFuture<Credential>
}

internal struct CredentialChain {
    
    internal static func createProvider(
        accessKeyId: String?,
        secretAccessKey: String?,
        sessionToken: String?,
        eventLoopGroup: EventLoopGroup,
        httpClient: AWSHTTPClient) -> CredentialProvider
    {
        if let accessKey = accessKeyId, let secretKey = secretAccessKey {
            let staticCredential = StaticCredential(accessKeyId: accessKey, secretAccessKey: secretKey, sessionToken: sessionToken)
            return StaticCredentialProv(credential: staticCredential, eventLoopGroup: eventLoopGroup)
        }
        
        if let credential = EnvironmentCredential(eventLoopGroup: eventLoopGroup) {
            return credential
        }
        
        if let scredential = try? SharedCredential(eventLoopGroup: eventLoopGroup) {
            return scredential
        }
        
        // if nothing has matched yet, we try to go for the MetaDataCredentialProviders on linux
        // on macOS we just create an empty static credential
        #if os(Linux)
        if let ecscredential = MetaDataCredentialProvider(eventLoopGroup: _eventloopGroup, client: ECSMetaDataClient(httpClient: httpClient)) {
            return ecscredential
        }
        else {
            return MetaDataCredentialProvider(eventLoopGroup: _eventloopGroup, client: InstanceMetaDataClient(httpClient: httpClient))
        }
        #else
        let staticCredential = StaticCredential(accessKeyId: "", secretAccessKey: "")
        return StaticCredentialProv(credential: staticCredential, eventLoopGroup: eventLoopGroup)
        #endif
    }
    
}
