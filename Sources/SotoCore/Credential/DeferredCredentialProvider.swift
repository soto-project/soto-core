//===----------------------------------------------------------------------===//
//
// This source file is part of the Soto for AWS open source project
//
// Copyright (c) 2017-2023 the Soto project authors
// Licensed under Apache License v2.0
//
// See LICENSE.txt for license information
// See CONTRIBUTORS.txt for the list of Soto project authors
//
// SPDX-License-Identifier: Apache-2.0
//
//===----------------------------------------------------------------------===//

import Logging
import NIOConcurrencyHelpers
import NIOCore

/// Wrap and store result from another credential provider.
///
/// Used for wrapping another credential provider whose `getCredential` method doesn't return instantly and
/// is only needed to be called once. After the wrapped `CredentialProvider` has generated a credential this is
/// returned instead of calling the wrapped `CredentialProvider's` `getCredentials` again.
public final class DeferredCredentialProvider: CredentialProvider {
    private let getCredentialTask: Task<Credential, Error>
    private let provider: CredentialProvider

    /// Create `DeferredCredentialProvider`.
    /// - Parameters:
    ///   - eventLoop: EventLoop that getCredential should run on
    ///   - provider: Credential provider to wrap
    public init(context: CredentialProviderFactory.Context, provider: CredentialProvider) {
        let description = "\(type(of: self))(\(provider.description))"
        self.getCredentialTask = Task {
            let credentials = try await provider.getCredential(logger: context.logger)
            context.logger.debug("AWS credentials ready", metadata: ["aws-credential-provider": .string(description)])
            return credentials
        }
        self.provider = provider
    }

    /// Shutdown credential provider
    public func shutdown() async throws {
        self.getCredentialTask.cancel()
        // ensure internal credential provider is not still running
        _ = try? await self.getCredential(logger: AWSClient.loggingDisabled)
        try await self.provider.shutdown()
    }

    /// Return credentials. If still in process of the getting credentials then return future result of `startupPromise`
    /// otherwise return credentials store in class
    /// - Parameter eventLoop: EventLoop to run off
    /// - Returns: EventLoopFuture that will hold credentials
    public func getCredential(logger: Logger) async throws -> Credential {
        try await withTaskCancellationHandler {
            try await self.getCredentialTask.value
        }
        onCancel: {
            self.getCredentialTask.cancel()
        }
    }
}

extension DeferredCredentialProvider: CustomStringConvertible {
    public var description: String { return "\(type(of: self))(\(self.provider.description))" }
}
