//===----------------------------------------------------------------------===//
//
// This source file is part of the Soto for AWS open source project
//
// Copyright (c) 2017-2020 the Soto project authors
// Licensed under Apache License v2.0
//
// See LICENSE.txt for license information
// See CONTRIBUTORS.txt for the list of Soto project authors
//
// SPDX-License-Identifier: Apache-2.0
//
//===----------------------------------------------------------------------===//

import Baggage
import NIO
import SotoSignerV4

/// Credential provider that always fails
public struct NullCredentialProvider: CredentialProvider {
    public init() {}

    public func getCredential(on eventLoop: EventLoop, context: LoggingContext) -> EventLoopFuture<Credential> {
        return eventLoop.makeFailedFuture(CredentialProviderError.noProvider)
    }
}
