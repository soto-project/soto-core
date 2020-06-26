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

import struct Foundation.Date
import struct Foundation.TimeInterval

public protocol ExpiringCredential: Credential {
    func isExpiring(within: TimeInterval) -> Bool
}

public extension ExpiringCredential {
    var isExpired: Bool {
        isExpiring(within: 0)
    }
}

/// Provide AWS credentials directly
struct RotatingCredential: ExpiringCredential {
    let accessKeyId: String
    let secretAccessKey: String
    let sessionToken: String?
    let expiration: Date?

    init(accessKeyId: String, secretAccessKey: String, sessionToken: String? = nil, expiration: Date? = nil) {
        self.accessKeyId = accessKeyId
        self.secretAccessKey = secretAccessKey
        self.sessionToken = sessionToken
        self.expiration = expiration
    }
    
    func isExpiring(within interval: TimeInterval) -> Bool {
        if let expiration = self.expiration {
            return expiration.timeIntervalSinceNow < interval
        }
        return false
    }
}
