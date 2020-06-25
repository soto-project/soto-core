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

/// Credential provider supplying credentials from environment variables
public final class EnvironmentCredentialProvider: CredentialProvider {
    var credential: Credential
    
    public init() {
        if let accessKeyId = Environment["AWS_ACCESS_KEY_ID"],
            let secretAccessKey = Environment["AWS_SECRET_ACCESS_KEY"] {
            self.credential = StaticCredential(
                accessKeyId: accessKeyId,
                secretAccessKey: secretAccessKey,
                sessionToken: Environment["AWS_SESSION_TOKEN"]
            )
        } else {
            self.credential = EmptyCredentialProvider()
        }
    }
    
    public func setup(with client:AWSClient) -> Bool {
        return !self.credential.isEmpty()
    }
    
    public func getCredential(on eventLoop: EventLoop) -> EventLoopFuture<Credential> {
        return eventLoop.makeSucceededFuture(credential)
    }
}
