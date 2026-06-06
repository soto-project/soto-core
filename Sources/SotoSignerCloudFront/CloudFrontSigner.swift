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

import Crypto
import NIOCore
import _CryptoExtras

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif

/// Generates signed URLs and cookies for Amazon CloudFront private content distribution.
public struct CloudFrontSigner: Sendable {

    // MARK: - Nested Types

    /// The hash algorithm used for signing
    public enum HashAlgorithm: String, Sendable {
        case sha1 = "SHA1"
        case sha256 = "SHA256"
    }

    /// Represents a custom policy for CloudFront signing
    public struct CustomPolicy: Sendable {
        /// Resource URL pattern (can include wildcards like `*`)
        public let resource: String
        /// How long before access expires (duration from `date`)
        public let expires: TimeAmount
        /// Optional: content not accessible until this duration after `date`
        public let activeFrom: TimeAmount?
        /// Optional IP address or CIDR range restriction
        public let ipAddress: String?

        public init(
            resource: String,
            expires: TimeAmount,
            activeFrom: TimeAmount? = nil,
            ipAddress: String? = nil
        ) {
            self.resource = resource
            self.expires = expires
            self.activeFrom = activeFrom
            self.ipAddress = ipAddress
        }
    }

    /// The three cookie values needed for CloudFront signed cookies
    public struct SignedCookies: Sendable {
        /// `CloudFront-Policy` value (custom policy only)
        public let policy: String?
        /// `CloudFront-Expires` value (canned policy only, epoch seconds)
        public let expires: Int?
        /// `CloudFront-Signature` value
        public let signature: String
        /// `CloudFront-Key-Pair-Id` value
        public let keyPairId: String
    }

    // MARK: - Properties

    let keyPairId: String
    let privateKey: _RSA.Signing.PrivateKey
    let hashAlgorithm: HashAlgorithm

    // MARK: - Initializers

    /// Initialize a CloudFront signer with a key pair ID and PEM-encoded private key (String).
    /// - Parameters:
    ///   - keyPairId: The CloudFront key pair ID (e.g., "K2JCJMDEHXQW5F")
    ///   - privateKey: PEM-encoded RSA private key as a String
    ///   - hashAlgorithm: Hash algorithm to use (defaults to `.sha1`)
    public init(keyPairId: String, privateKey: String, hashAlgorithm: HashAlgorithm = .sha1) throws {
        self.keyPairId = keyPairId
        self.hashAlgorithm = hashAlgorithm
        do {
            self.privateKey = try _RSA.Signing.PrivateKey(pemRepresentation: privateKey)
        } catch {
            throw CloudFrontSignerError.invalidPrivateKey
        }
    }

    /// Initialize a CloudFront signer with a key pair ID and PEM-encoded private key (Data).
    /// - Parameters:
    ///   - keyPairId: The CloudFront key pair ID (e.g., "K2JCJMDEHXQW5F")
    ///   - privateKey: PEM-encoded RSA private key as Data
    ///   - hashAlgorithm: Hash algorithm to use (defaults to `.sha1`)
    public init(keyPairId: String, privateKey: Data, hashAlgorithm: HashAlgorithm = .sha1) throws {
        let pemString = String(decoding: privateKey, as: UTF8.self)
        try self.init(keyPairId: keyPairId, privateKey: pemString, hashAlgorithm: hashAlgorithm)
    }
}
