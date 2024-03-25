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

#if compiler(<5.9) && os(Linux)
@preconcurrency import struct Foundation.Date
#else
import struct Foundation.Date
#endif
import struct Foundation.TimeInterval
import SotoSignerV4

/// Credential provider whose credentials expire over tiem.
public protocol ExpiringCredential: Credential {
    var expiration: Date { get }
}

public extension ExpiringCredential {
    /// Will credential expire within a certain time
    func isExpiring(within interval: TimeInterval) -> Bool {
        return self.expiration.timeIntervalSinceNow < interval
    }

    /// Has credential expired
    var isExpired: Bool {
        self.isExpiring(within: 0)
    }
}

/// Basic implementation of a struct conforming to ExpiringCredential.
public struct RotatingCredential: ExpiringCredential {
    public init(accessKeyId: String, secretAccessKey: String, sessionToken: String?, expiration: Date) {
        self.accessKeyId = accessKeyId
        self.secretAccessKey = secretAccessKey
        self.sessionToken = sessionToken
        self.expiration = expiration
    }

    public let accessKeyId: String
    public let secretAccessKey: String
    public let sessionToken: String?
    public let expiration: Date
}
