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
    enum _CredentialProviderError {
        case noProvider
    }

    let error: _CredentialProviderError

    public static var noProvider: CredentialProviderError { return .init(error: .noProvider) }
}

extension CredentialProviderError: CustomStringConvertible {
    public var description: String {
        switch self.error {
        case .noProvider:
            return "No credential provider found"
        }
    }
}
