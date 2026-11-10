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
@nonexhaustive
public enum CloudFrontSignerError: Error {
    case invalidPrivateKey
    case invalidURL
    case signingFailed
}
