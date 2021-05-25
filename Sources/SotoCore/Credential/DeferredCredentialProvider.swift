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
import NIOConcurrencyHelpers

/// Used for wrapping another credential provider whose `getCredential` method doesn't return instantly and
/// is only needed to be called once. After the wrapped `CredentialProvider` has generated a credential this is
/// returned instead of calling the wrapped `CredentialProvider's` `getCredentials` again.
public class DeferredCredentialProvider: CredentialProvider {
    let lock = Lock()
    var credential: Credential? {
        get {
            self.lock.withLock {
                internalCredential
            }
        }
        set {
            self.lock.withLock {
                internalCredential = newValue
            }
        }
    }

    private var provider: CredentialProvider
    private var startupPromise: EventLoopPromise<Credential>
    private var internalCredential: Credential?

    /// Create `DeferredCredentialProvider`.
    /// - Parameters:
    ///   - eventLoop: EventLoop that getCredential should run on
    ///   - provider: Credential provider to wrap
    public init(context: CredentialProviderFactory.Context, provider: CredentialProvider) {
        self.startupPromise = context.eventLoop.makePromise(of: Credential.self)
        self.provider = provider
        provider.getCredential(on: context.eventLoop, context: context.context)
            .flatMapErrorThrowing { _ in throw CredentialProviderError.noProvider }
            .map { credential in
                self.credential = credential
                context.context.logger.debug("AWS credentials ready", metadata: ["aws-credential-provider": .string("\(self)")])
                return credential
            }
            .cascade(to: self.startupPromise)
    }

    /// Shutdown credential provider
    public func shutdown(on eventLoop: EventLoop) -> EventLoopFuture<Void> {
        return self.startupPromise.futureResult
            .and(self.provider.shutdown(on: eventLoop))
            .map { _ in }
            .hop(to: eventLoop)
    }

    /// Return credentials. If still in process of the getting credentials then return future result of `startupPromise`
    /// otherwise return credentials store in class
    /// - Parameter eventLoop: EventLoop to run off
    /// - Returns: EventLoopFuture that will hold credentials
    public func getCredential(on eventLoop: EventLoop, context: LoggingContext) -> EventLoopFuture<Credential> {
        if let credential = self.credential {
            return eventLoop.makeSucceededFuture(credential)
        }

        return self.startupPromise.futureResult.hop(to: eventLoop)
    }
}

extension DeferredCredentialProvider: CustomStringConvertible {
    public var description: String { return "\(type(of: self))(\(self.provider.description))" }
}
