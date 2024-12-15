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

/// Empty credentials
public struct EmptyCredential: CredentialProvider, Credential {
    public var accessKeyId: String { "" }
    public var secretAccessKey: String { "" }
    public var sessionToken: String? { nil }

    public func getCredential(logger: Logger) async throws -> any Credential {
        self
    }
}
