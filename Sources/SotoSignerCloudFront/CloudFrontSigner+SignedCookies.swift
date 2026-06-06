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

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif
import NIOCore

extension CloudFrontSigner {

    /// Generate signed cookies using a canned policy.
    /// - Parameters:
    ///   - url: The resource URL the cookies grant access to
    ///   - expires: How long before the cookies expire
    ///   - date: Date that cookies are valid from, defaults to now
    /// - Returns: The cookie values to set in `Set-Cookie` headers
    public func signedCookies(url: String, expires: TimeAmount, date: Date = Date()) throws -> SignedCookies {
        // 1. Compute expiration epoch
        let epoch = Int(date.timeIntervalSince1970) + Int(expires.nanoseconds / 1_000_000_000)

        // 2. Construct canned policy JSON
        let policy = cannedPolicyStatement(resource: url, expiresEpoch: epoch)

        // 3. Sign the policy bytes
        let signatureData = try sign(Array(policy.utf8))

        // 4. CloudFront base64-encode the signature
        let encodedSignature = Self.cloudFrontBase64Encode(signatureData)

        // 5. Return SignedCookies with expires (canned policy: no encoded policy field)
        return SignedCookies(
            policy: nil,
            expires: epoch,
            signature: encodedSignature,
            keyPairId: keyPairId
        )
    }

    /// Generate signed cookies using a custom policy.
    /// - Parameters:
    ///   - policy: Custom policy specifying access conditions
    ///   - date: Date that cookies are valid from, defaults to now
    /// - Returns: The cookie values to set in `Set-Cookie` headers
    public func signedCookies(policy: CustomPolicy, date: Date = Date()) throws -> SignedCookies {
        // 1. Compute expiration epoch
        let expiresEpoch = Int(date.timeIntervalSince1970) + Int(policy.expires.nanoseconds / 1_000_000_000)

        // 2. Optionally compute activeFrom epoch
        let activeFromEpoch: Int? = policy.activeFrom.map {
            Int(date.timeIntervalSince1970) + Int($0.nanoseconds / 1_000_000_000)
        }

        // 3. Construct custom policy JSON
        let policyString = customPolicyStatement(
            resource: policy.resource,
            expiresEpoch: expiresEpoch,
            activeFromEpoch: activeFromEpoch,
            ipAddress: policy.ipAddress
        )

        // 4. CloudFront base64-encode the policy string
        let encodedPolicy = Self.cloudFrontBase64Encode(Data(policyString.utf8))

        // 5. Sign the policy bytes
        let signatureData = try sign(Array(policyString.utf8))

        // 6. CloudFront base64-encode the signature
        let encodedSignature = Self.cloudFrontBase64Encode(signatureData)

        // 7. Return SignedCookies with encoded policy (custom policy: no expires field)
        return SignedCookies(
            policy: encodedPolicy,
            expires: nil,
            signature: encodedSignature,
            keyPairId: keyPairId
        )
    }
}
