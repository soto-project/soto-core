//===----------------------------------------------------------------------===//
//
// This source file is part of the Soto for AWS open source project
//
// Copyright (c) 2017-2022 the Soto project authors
// Licensed under Apache License v2.0
//
// See LICENSE.txt for license information
// See CONTRIBUTORS.txt for the list of Soto project authors
//
// SPDX-License-Identifier: Apache-2.0
//
//===----------------------------------------------------------------------===//

import Logging
import NIOCore
import SotoSignerV4

/// Async Protocol for providing AWS credentials
public protocol AsyncCredentialProvider: CredentialProvider {
    /// Return credential
    /// - Parameters:
    ///   - eventLoop: EventLoop to run on
    ///   - logger: Logger to use
    func getCredential(on eventLoop: EventLoop, logger: Logger) async throws -> Credential
}

extension AsyncCredentialProvider {
    public func getCredential(on eventLoop: EventLoop, logger: Logger) -> EventLoopFuture<Credential> {
        let promise = eventLoop.makePromise(of: Credential.self)
        promise.completeWithTask { try await self.getCredential(on: eventLoop, logger: logger) }
        return promise.futureResult
    }
}
