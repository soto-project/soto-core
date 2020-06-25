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

struct EmptyCredentialProvider: Credential, CredentialProvider {
    var accessKeyId: String = ""
    var secretAccessKey: String = ""
    var sessionToken: String? = nil
    
    public func getCredential(on eventLoop: EventLoop) -> EventLoopFuture<Credential> {
        eventLoop.makeSucceededFuture(self)
    }
}
