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
import _CryptoExtras

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif

extension CloudFrontSigner {

    /// Apply CloudFront's URL-safe base64 encoding.
    ///
    /// Standard base64 is produced first, then the following replacements are applied:
    /// - `+` → `-`
    /// - `=` → `_`
    /// - `/` → `~`
    ///
    /// Note: This is NOT standard base64url (RFC 4648 §5) — CloudFront uses `~` for `/`
    /// and `_` for padding `=`, which differs from base64url's `_` for `/` with padding kept.
    /// While `.base64URLAlphabet` (macOS 26.4+) could be used as a starting point with
    /// two additional replacements (`_` → `~`, `=` → `_`), it offers no simplification
    /// over the current approach and requires a newer deployment target.
    static func cloudFrontBase64Encode(_ data: Data) -> String {
        let base64 = data.base64EncodedString()
        var result = ""
        result.reserveCapacity(base64.count)
        for character in base64 {
            switch character {
            case "+":
                result.append("-")
            case "=":
                result.append("_")
            case "/":
                result.append("~")
            default:
                result.append(character)
            }
        }
        return result
    }

    /// Construct a canned policy JSON statement with no whitespace.
    ///
    /// Format: `{"Statement":[{"Resource":"<resource>","Condition":{"DateLessThan":{"AWS:EpochTime":<epoch>}}}]}`
    func cannedPolicyStatement(resource: String, expiresEpoch: Int) -> String {
        "{\"Statement\":[{\"Resource\":\"\(resource)\",\"Condition\":{\"DateLessThan\":{\"AWS:EpochTime\":\(expiresEpoch)}}}]}"
    }

    /// Sign raw data using RSA PKCS#1 v1.5 with the configured hash algorithm.
    ///
    /// The raw policy bytes are passed in — this method handles digest computation
    /// before signing with the RSA private key.
    ///
    /// - Parameter data: The raw policy statement bytes to sign.
    /// - Returns: The raw RSA signature bytes.
    /// - Throws: `CloudFrontSignerError.signingFailed` if the signing operation fails.
    func sign(_ data: [UInt8]) throws -> Data {
        do {
            let signature: _RSA.Signing.RSASignature
            switch self.hashAlgorithm {
            case .sha1:
                let digest = Insecure.SHA1.hash(data: data)
                signature = try self.privateKey.signature(for: digest, padding: .insecurePKCS1v1_5)
            case .sha256:
                let digest = SHA256.hash(data: data)
                signature = try self.privateKey.signature(for: digest, padding: .insecurePKCS1v1_5)
            }
            return signature.rawRepresentation
        } catch {
            throw CloudFrontSignerError.signingFailed
        }
    }

    /// Construct a custom policy JSON statement with no whitespace.
    ///
    /// Includes optional `DateGreaterThan` and `IpAddress` conditions when provided.
    func customPolicyStatement(resource: String, expiresEpoch: Int, activeFromEpoch: Int?, ipAddress: String?) -> String {
        var conditions = "\"DateLessThan\":{\"AWS:EpochTime\":\(expiresEpoch)}"

        if let activeFromEpoch {
            conditions += ",\"DateGreaterThan\":{\"AWS:EpochTime\":\(activeFromEpoch)}"
        }

        if let ipAddress {
            conditions += ",\"IpAddress\":{\"AWS:SourceIp\":\"\(ipAddress)\"}"
        }

        return "{\"Statement\":[{\"Resource\":\"\(resource)\",\"Condition\":{\(conditions)}}]}"
    }
}
