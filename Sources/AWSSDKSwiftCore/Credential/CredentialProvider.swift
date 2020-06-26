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

public struct CredentialProviderFactory {
    
    public struct Context {
        let httpClient: AWSHTTPClient
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
    
    public static func custom(_ factory: @escaping (Context) -> CredentialProvider) -> CredentialProviderFactory {
        Self(cb: factory)
    }
    
    public static var environment: CredentialProviderFactory {
        Self() { _ in
            if let accessKeyId = Environment["AWS_ACCESS_KEY_ID"],
                let secretAccessKey = Environment["AWS_SECRET_ACCESS_KEY"] {
                return StaticCredential(
                    accessKeyId: accessKeyId,
                    secretAccessKey: secretAccessKey,
                    sessionToken: Environment["AWS_SESSION_TOKEN"]
                )
            } else {
                return NullCredentialProvider()
            }
        }
    }
    
    public static func `static`(accessKeyId: String, secretAccessKey: String, sessionToken: String? = nil) -> CredentialProviderFactory {
        Self() { _ in
            StaticCredential(
                accessKeyId: accessKeyId,
                secretAccessKey: secretAccessKey,
                sessionToken: sessionToken
            )
        }
    }

    public static var ecs: CredentialProviderFactory {
        Self() { context in
            if let client = ECSMetaDataClient(httpClient: context.httpClient) {
                return RotatingCredentialProvider(eventLoop: context.eventLoop, client: client)
            }
            
            // fallback
            return NullCredentialProvider()
        }
    }
    
    public static var ec2: CredentialProviderFactory {
        Self() { context in
            let client = InstanceMetaDataClient(httpClient: context.httpClient)
            return RotatingCredentialProvider(eventLoop: context.eventLoop, client: client)
        }
    }
    
    public static var runtime: CredentialProviderFactory {
        Self() { context in
            RuntimeCredentialProvider.createProvider(
                on: context.eventLoop,
                httpClient: context.httpClient)
        }
    }
    
    public static var empty: CredentialProviderFactory {
        Self() { context in
            StaticCredential(accessKeyId: "", secretAccessKey: "")
        }
    }
}
