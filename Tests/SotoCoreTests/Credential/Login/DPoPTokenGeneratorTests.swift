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

// DPoP Token Generator Tests

import Crypto
import Testing

@testable import SotoCore

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif

@Suite("DPoP Token Generator")
struct DPoPTokenGeneratorTests {

    struct TestTimeProvider: TimeProvider {
        func generate() -> Int { 1_234_567_890 }
    }

    struct TestJTIGenerator: JTIGenerator {
        func generate() -> String { "test-jti-123" }
    }

    @Test("Generate DPoP header with valid EC key")
    func generateDPoPHeaderWithValidKey() throws {
        // Generate a test EC key
        let privateKey = P256.Signing.PrivateKey()
        let pemKey = privateKey.pemRepresentation

        // Create generator with fixed values for testing
        let generator = DPoPTokenGenerator(
            jtiGenerator: TestJTIGenerator(),
            timeProvider: TestTimeProvider()
        )

        // Generate DPoP header
        let header = try generator.generateDPoPHeader(
            endpoint: "https://us-east-1.signin.aws.amazon.com/v1/token",
            httpMethod: "POST",
            pemKey: pemKey
        )

        // Verify JWT structure (header.payload.signature)
        let parts = header.split(separator: ".")
        #expect(parts.count == 3, "JWT should have 3 parts")

        // Decode and verify header
        let headerData = try #require(Data(base64URLEncoded: String(parts[0])))
        let decodedHeader = try JSONDecoder().decode(JWTHeaderTest.self, from: headerData)
        #expect(decodedHeader.typ == "dpop+jwt")
        #expect(decodedHeader.alg == "ES256")
        #expect(decodedHeader.jwk.kty == "EC")
        #expect(decodedHeader.jwk.crv == "P-256")
        #expect(!decodedHeader.jwk.x.isEmpty)
        #expect(!decodedHeader.jwk.y.isEmpty)

        // Decode and verify payload
        let payloadData = try #require(Data(base64URLEncoded: String(parts[1])))
        let decodedPayload = try JSONDecoder().decode(JWTPayloadTest.self, from: payloadData)
        #expect(decodedPayload.jti == "test-jti-123")
        #expect(decodedPayload.htm == "POST")
        #expect(decodedPayload.htu == "https://us-east-1.signin.aws.amazon.com/v1/token")
        #expect(decodedPayload.iat == 1_234_567_890)

        // Verify signature exists
        let signatureData = try #require(Data(base64URLEncoded: String(parts[2])))
        #expect(signatureData.count == 64, "P-256 signature should be 64 bytes")
    }

    @Test("Generate DPoP header with invalid key throws error")
    func generateDPoPHeaderWithInvalidKey() {
        let generator = DPoPTokenGenerator()
        let invalidPemKey = "invalid-pem-key"

        do {
            _ = try generator.generateDPoPHeader(
                endpoint: "https://test.com",
                httpMethod: "POST",
                pemKey: invalidPemKey
            )
            Issue.record("Expected tokenParseFailed error")
        } catch let error as AWSLoginCredentialError {
            #expect(error.code == "tokenParseFailed")
        } catch {
            Issue.record("Unexpected error type: \(error)")
        }
    }

    @Test("Generate DPoP header with different HTTP methods", arguments: ["GET", "POST", "PUT", "DELETE"])
    func generateDPoPHeaderWithDifferentHTTPMethods(method: String) throws {
        let privateKey = P256.Signing.PrivateKey()
        let pemKey = privateKey.pemRepresentation
        let generator = DPoPTokenGenerator()

        let header = try generator.generateDPoPHeader(
            endpoint: "https://test.com",
            httpMethod: method,
            pemKey: pemKey
        )

        let parts = header.split(separator: ".")
        let payloadData = try #require(Data(base64URLEncoded: String(parts[1])))
        let payload = try JSONDecoder().decode(JWTPayloadTest.self, from: payloadData)

        #expect(payload.htm == method)
    }
}

// Test helper structs
private struct JWTHeaderTest: Codable {
    let typ: String
    let alg: String
    let jwk: JWKTest
}

private struct JWKTest: Codable {
    let kty: String
    let crv: String
    let x: String
    let y: String
}

private struct JWTPayloadTest: Codable {
    let jti: String
    let htm: String
    let htu: String
    let iat: Int
}

// Base64URL decoding extension
extension Data {
    init?(base64URLEncoded string: String) {
        var base64 =
            string
            .replacing("-", with: "+")
            .replacing("_", with: "/")

        // Add padding if needed
        let remainder = base64.count % 4
        if remainder > 0 {
            base64 += String(repeating: "=", count: 4 - remainder)
        }

        self.init(base64Encoded: base64)
    }
}
