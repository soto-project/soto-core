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

// DPoP Token Generator - JWT with EC Signing

import Crypto
import Foundation

@available(macOS 13.0, iOS 14.0, tvOS 14.0, watchOS 7.0, *)
struct DPoPTokenGenerator<JTI: JTIGenerator, Time: TimeProvider> {

    // allow to inject these two values during the tests
    private let jtiGenerator: JTI
    private let timeProvider: Time

    init(
        jtiGenerator: JTI = DefaultJTIGenerator(),
        timeProvider: Time = DefaultTimeProvider()
    ) {
        self.jtiGenerator = jtiGenerator
        self.timeProvider = timeProvider
    }

    private struct JWK: Codable {
        let kty: String
        let crv: String
        let x: String
        let y: String
    }

    private struct JWTHeader: Codable {
        let typ: String
        let alg: String
        let jwk: JWK
    }

    private struct JWTPayload: Codable {
        let jti: String
        let htm: String
        let htu: String
        let iat: Int
    }

    private func base64URLEncode(_ data: Data) -> String {
        data.base64EncodedString()
            .replacing("+", with: "-")
            .replacing("/", with: "_")
            .replacing("=", with: "")
    }

    private func extractPublicKeyCoordinates(from pemKey: String) -> (x: String, y: String)? {
        // Use swift-crypto's built-in PEM support to load the key
        guard let privateKey = try? P256.Signing.PrivateKey(pemRepresentation: pemKey) else {
            return nil
        }

        // Get the public key and extract x963 representation
        let publicKey = privateKey.publicKey
        let x963Data = publicKey.x963Representation

        // X963 format for uncompressed point: 0x04 + x (32 bytes) + y (32 bytes)
        guard x963Data.count == 65, x963Data[0] == 0x04 else {
            return nil
        }

        let xData = x963Data[1..<33]
        let yData = x963Data[33..<65]

        return (
            x: base64URLEncode(xData),
            y: base64URLEncode(yData)
        )
    }

    private func signWithEC(message: Data, pemKey: String) throws -> Data {
        // Use swift-crypto's built-in PEM support
        let privateKey = try P256.Signing.PrivateKey(pemRepresentation: pemKey)

        // Sign the message (Crypto automatically hashes with SHA-256 for ES256)
        let signature = try privateKey.signature(for: message)

        // Return raw signature (r + s concatenated, 64 bytes for P-256)
        return signature.rawRepresentation
    }

    func generateDPoPHeader(
        endpoint: String,
        httpMethod: String = "POST",
        pemKey: String
    ) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys

        // Extract public key coordinates from PEM
        guard let (x, y) = extractPublicKeyCoordinates(from: pemKey) else {
            throw LoginError.tokenParseFailed
        }

        // JWT header
        let header = JWTHeader(
            typ: "dpop+jwt",
            alg: "ES256",
            jwk: JWK(kty: "EC", crv: "P-256", x: x, y: y)
        )

        // JWT payload
        let payload = JWTPayload(
            jti: jtiGenerator.generate(),
            htm: httpMethod,
            htu: endpoint,
            iat: timeProvider.generate()
        )

        let headerData = try encoder.encode(header)
        let payloadData = try encoder.encode(payload)

        let headerB64 = base64URLEncode(headerData)
        let payloadB64 = base64URLEncode(payloadData)

        let message = "\(headerB64).\(payloadB64)"
        let messageData = message.data(using: .utf8)!

        // Sign the message with EC private key
        let signatureData = try signWithEC(message: messageData, pemKey: pemKey)
        let signatureB64 = base64URLEncode(signatureData)

        return "\(message).\(signatureB64)"
    }
}

protocol JTIGenerator: Sendable {
    func generate() -> String
}

struct DefaultJTIGenerator: JTIGenerator {
    func generate() -> String {
        UUID().uuidString
    }
}

protocol TimeProvider: Sendable {
    func generate() -> Int
}

struct DefaultTimeProvider: TimeProvider {
    func generate() -> Int {
        Int(Date().timeIntervalSince1970)
    }
}
