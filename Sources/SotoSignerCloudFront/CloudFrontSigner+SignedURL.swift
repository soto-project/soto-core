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

    /// Generate a signed URL using a canned policy.
    /// - Parameters:
    ///   - url: The CloudFront URL to sign
    ///   - expires: How long before the signed URL expires
    ///   - date: Date that URL is valid from, defaults to now
    /// - Returns: The complete signed URL
    public func signedURL(url: String, expires: TimeAmount, date: Date = Date()) throws -> String {
        // 1. Compute expiration epoch
        let epoch = Int(date.timeIntervalSince1970) + Int(expires.nanoseconds / 1_000_000_000)

        // 2. Construct canned policy JSON
        let policy = cannedPolicyStatement(resource: url, expiresEpoch: epoch)

        // 3. Sign the policy bytes
        let signatureData = try sign(Array(policy.utf8))

        // 4. CloudFront base64-encode the signature
        let encodedSignature = Self.cloudFrontBase64Encode(signatureData)

        // 5. Determine separator
        let separator: Character = url.contains("?") ? "&" : "?"

        // 6. Build the signed URL
        var signedURL = "\(url)\(separator)Expires=\(epoch)&Signature=\(encodedSignature)&Key-Pair-Id=\(keyPairId)"

        // 7. Append Hash-Algorithm if SHA-256
        if hashAlgorithm == .sha256 {
            signedURL += "&Hash-Algorithm=SHA256"
        }

        return signedURL
    }

    /// Generate a signed URL using a custom policy.
    /// - Parameters:
    ///   - url: The CloudFront URL to sign
    ///   - policy: Custom policy specifying access conditions
    ///   - date: Date that URL is valid from, defaults to now
    /// - Returns: The complete signed URL
    public func signedURL(url: String, policy: CustomPolicy, date: Date = Date()) throws -> String {
        // 1. Compute expiration epoch
        let expiresEpoch = Int(date.timeIntervalSince1970) + Int(policy.expires.nanoseconds / 1_000_000_000)

        // 2. Optionally compute activeFrom epoch
        let activeFromEpoch: Int? = policy.activeFrom.map {
            Int(date.timeIntervalSince1970) + Int($0.nanoseconds / 1_000_000_000)
        }

        // 3. Construct custom policy JSON (use policy.resource, not url)
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

        // 7. Determine separator
        let separator: Character = url.contains("?") ? "&" : "?"

        // 8. Build the signed URL
        var signedURL = "\(url)\(separator)Policy=\(encodedPolicy)&Signature=\(encodedSignature)&Key-Pair-Id=\(keyPairId)"

        // 9. Append Hash-Algorithm if SHA-256
        if hashAlgorithm == .sha256 {
            signedURL += "&Hash-Algorithm=SHA256"
        }

        return signedURL
    }
}
