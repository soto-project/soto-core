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

public struct CredentialProviderError: Error, Equatable {
    enum _CredentialProviderError {
        case noCredentials
        case noProvider
    }
    let error: _CredentialProviderError
    
    public static var noCredentials: CredentialProviderError { return .init(error: .noCredentials) }
    public static var noProvider: CredentialProviderError { return .init(error: .noProvider) }
}
