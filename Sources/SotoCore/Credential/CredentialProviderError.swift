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

public struct CredentialProviderError: Error, Equatable {
    enum _CredentialProviderError: Equatable {
        case noProvider
        case tokenIdFileFailedToLoad
    }

    let error: _CredentialProviderError

    public static var noProvider: CredentialProviderError { .init(error: .noProvider) }
    public static var tokenIdFileFailedToLoad: CredentialProviderError { .init(error: .tokenIdFileFailedToLoad) }
}

extension CredentialProviderError: CustomStringConvertible {
    public var description: String {
        switch self.error {
        case .noProvider:
            return "No credential provider found."
        case .tokenIdFileFailedToLoad:
            return "WebIdentity token id file failed to load."
        }
    }
}
