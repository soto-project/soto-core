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

import Logging
import NIO
import NIOConcurrencyHelpers

/// Used for wrapping another credential provider whose `getCredential` method doesn't return instantly and
/// it only needs to be called once. After the wrapped `CredentialProvider` has generated a credential this is
/// returned instead of calling the wrapped `CredentialProvider's` `getCredentials` again.
public class DeferredCredentialProvider: CredentialProvider {
    let lock = Lock()
    var credential: Credential? {
        get {
            self.lock.withLock {
                internalCredential
            }
        }
    }

    private var provider: CredentialProvider
    private var startupPromise: EventLoopPromise<Credential>
    private var internalCredential: Credential? = nil

    /// Create `DeferredCredentialProvider`.
    /// - Parameters:
    ///   - eventLoop: EventLoop that getCredential should run on
    ///   - provider: Credential provider to wrap
    public init(context: CredentialProviderFactory.Context, provider: CredentialProvider) {
        self.startupPromise = context.eventLoop.makePromise(of: Credential.self)
        self.provider = provider
        provider.getCredential(on: context.eventLoop, logger: context.logger)
            .flatMapErrorThrowing { _ in throw CredentialProviderError.noProvider }
            .map { credential in
                self.internalCredential = credential
                return credential
            }
            .cascade(to: self.startupPromise)
    }

    public func shutdown(on eventLoop: EventLoop) -> EventLoopFuture<Void> {
        return startupPromise.futureResult
            .and(provider.shutdown(on: eventLoop))
            .map { _ in }
            .hop(to: eventLoop)
    }

    /// Return credentials. If still in process of the getting credentials then return future result of `startupPromise`
    /// otherwise return credentials store in class
    /// - Parameter eventLoop: EventLoop to run off
    /// - Returns: EventLoopFuture that will hold credentials
    public func getCredential(on eventLoop: EventLoop, logger: Logger) -> EventLoopFuture<Credential> {
        if let credential = self.credential {
            return eventLoop.makeSucceededFuture(credential)
        }

        return self.startupPromise.futureResult.hop(to: eventLoop)
    }
}

extension DeferredCredentialProvider: CustomStringConvertible {
    public var description: String { return "\(type(of:self))(\(provider.description))"}
}
