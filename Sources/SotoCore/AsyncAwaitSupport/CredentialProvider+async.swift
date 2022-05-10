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

#if compiler(>=5.5.2) && canImport(_Concurrency)

#if compiler(>=5.6)
@preconcurrency import Logging
@preconcurrency import NIOCore
#else
import Logging
import NIOCore
#endif
import SotoSignerV4

/// Async Protocol for providing credentials
@available(macOS 10.15, iOS 13.0, tvOS 13.0, watchOS 6.0, *)
public protocol AsyncCredentialProvider: CredentialProvider {
    /// Return credential
    /// - Parameters:
    ///   - eventLoop: EventLoop to run on
    ///   - logger: Logger to use
    func getCredential(on eventLoop: EventLoop, logger: Logger) async throws -> Credential
}

@available(macOS 10.15, iOS 13.0, tvOS 13.0, watchOS 6.0, *)
extension AsyncCredentialProvider {
    public func getCredential(on eventLoop: EventLoop, logger: Logger) -> EventLoopFuture<Credential> {
        let promise = eventLoop.makePromise(of: Credential.self)
        promise.completeWithTask { try await getCredential(on: eventLoop, logger: logger) }
        return promise.futureResult
    }
}

#endif // compiler(>=5.5.2) && canImport(_Concurrency)
