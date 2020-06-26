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

import AWSSignerV4

extension StaticCredential: CredentialProvider {
    public func getCredential(on eventLoop: EventLoop) -> EventLoopFuture<Credential> {
        eventLoop.makeSucceededFuture(self)
    }
}

extension StaticCredential: CredentialProviderWrapper {
    public func getProvider(httpClient: AWSHTTPClient, on eventLoop: EventLoop) -> CredentialProvider {
        return self
    }
}
