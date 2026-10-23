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

#if canImport(FoundationEssentials)
public import FoundationEssentials
#else
public import Foundation
#endif

/// Basic credential details for accessing AWS services
public struct Credential: Equatable, Sendable {
    public var accessKeyId: String
    public var secretAccessKey: String
    public var sessionToken: String?
    public var expiration: Date

    public init(accessKeyId: String, secretAccessKey: String, sessionToken: String? = nil, expiration: Date = .distantFuture) {
        self.accessKeyId = accessKeyId
        self.secretAccessKey = secretAccessKey
        self.sessionToken = sessionToken
        self.expiration = expiration
    }

    /// Will credential expire within a certain time
    public func isExpiring(within interval: TimeInterval) -> Bool {
        self.expiration.timeIntervalSinceNow < interval
    }

    /// Has credential expired
    public var isExpired: Bool {
        self.isExpiring(within: 0)
    }

    public static var empty: Credential { .init(accessKeyId: "", secretAccessKey: "") }
}
