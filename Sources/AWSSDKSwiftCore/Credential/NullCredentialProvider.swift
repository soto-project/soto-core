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
struct NullCredentialProvider: CredentialProvider {
    public func getCredential(on eventLoop: EventLoop) -> EventLoopFuture<Credential> {
        return eventLoop.makeFailedFuture(CredentialProviderError.noProvider)
    }
}
