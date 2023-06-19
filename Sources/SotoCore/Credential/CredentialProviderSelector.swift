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

/// Protocol for CredentialProvider that uses an internal CredentialProvider generated by another Task
protocol CredentialProviderSelector: CredentialProvider, AnyObject {
    func getTaskProviderTask() async throws -> CredentialProvider
    func cancelGetTaskProviderTask()
}

extension CredentialProviderSelector {
    func getCredential(logger: Logger) async throws -> Credential {
        try await withTaskCancellationHandler {
            let provider = try await getTaskProviderTask()
            return try await provider.getCredential(logger: logger)
        }
        onCancel: {
            cancelGetTaskProviderTask()
        }
    }

    func shutdown() async throws {
        cancelGetTaskProviderTask()
        let provider = try await getTaskProviderTask()
        try await provider.shutdown()
    }
}
