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
import NIOConcurrencyHelpers
import NIOCore
import SotoSignerV4

/// get credentials from a list of possible credential providers. Goes through list of providers from start to end
/// attempting to get credentials. Once it finds a `CredentialProvider` that supplies credentials use that
/// one
final class RuntimeSelectorCredentialProvider: CredentialProviderSelector {
    private let getProviderTask: Task<CredentialProvider, Error>

    init(providers: [CredentialProviderFactory], context: CredentialProviderFactory.Context) {
        self.getProviderTask = Task {
            try await Self.setupInternalProvider(providers: providers, context: context)
        }
    }

    func getTaskProviderTask() async throws -> CredentialProvider {
        try await self.getProviderTask.value
    }

    func cancelGetTaskProviderTask() {
        self.getProviderTask.cancel()
    }

    /// goes through list of providers. If provider is able to provide credentials then use that one, otherwise move onto the next
    /// provider in the list
    private static func setupInternalProvider(
        providers: [CredentialProviderFactory],
        context: CredentialProviderFactory.Context
    ) async throws -> CredentialProvider {
        for providerFactory in providers {
            let provider = providerFactory.createProvider(context: context)
            do {
                _ = try await provider.getCredential(logger: context.logger)
                context.logger.debug("Select credential provider", metadata: ["aws-credential-provider": .string("\(provider)")])
                return provider
            } catch {
                context.logger.log(level: context.options.errorLogLevel, "Select credential provider failed")
            }
        }
        return NullCredentialProvider()
    }
}
