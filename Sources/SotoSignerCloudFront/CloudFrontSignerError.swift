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
public enum CloudFrontSignerError: Error, Sendable {
    /// The provided PEM data could not be parsed as an RSA private key
    case invalidPrivateKey
    /// The URL string is not valid
    case invalidURL
    /// The signing operation failed
    case signingFailed
}
