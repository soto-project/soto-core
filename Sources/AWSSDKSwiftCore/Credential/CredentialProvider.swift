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
