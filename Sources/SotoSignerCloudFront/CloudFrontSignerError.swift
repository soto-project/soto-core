//===----------------------------------------------------------------------===//
//
// This source file is part of the Soto for AWS open source project
//
// Copyright (c) 2017-2026 the Soto project authors
// Licensed under Apache License v2.0
//
// See LICENSE.txt for license information
// See CONTRIBUTORS.txt for the list of Soto project authors
//
// SPDX-License-Identifier: Apache-2.0
//
//===----------------------------------------------------------------------===//

/// Errors that can occur during CloudFront signing operations
public struct CloudFrontSignerError: Error, Sendable, Equatable {

    private enum Code: String, Sendable {
        case invalidPrivateKey
        case invalidURL
        case signingFailed
    }

    private let code: Code

    private init(_ code: Code) {
        self.code = code
    }

    /// The provided PEM/DER data could not be parsed as an RSA private key
    public static let invalidPrivateKey = CloudFrontSignerError(.invalidPrivateKey)
    /// The URL string is not valid
    public static let invalidURL = CloudFrontSignerError(.invalidURL)
    /// The signing operation failed
    public static let signingFailed = CloudFrontSignerError(.signingFailed)
}
