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
import Testing
import _CryptoExtras

@testable import SotoSignerCloudFront

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif

// MARK: - Test RSA Key Pair (2048-bit, generated with openssl genrsa 2048)

private let testPrivateKeyPEM = """
    -----BEGIN PRIVATE KEY-----
    MIIEvQIBADANBgkqhkiG9w0BAQEFAASCBKcwggSjAgEAAoIBAQCdgqCn15xMqhO4
    QodcpLxQKR1GGd3RzmkkyxVhaBVuz0YurkzgX1jHGxRq9uRz6J9QYz4E4iCiq8b9
    XODEt+MpD1tL0TKjvXxrS6W2/ht/he5lCnhLTHPXM2geVEEzAVQ8V2h9kFy+iui6
    w6oN9puKs0XpeW3rga4SAjyq1HYmbdPdhvI6XQ5RhIPyyg9tTffAVzlJS1sttBcq
    Vb7g4730mkMAHYkwXpAeK4GfdRq+MOQiKCTQPNPUsU4K625UnydRwMG2TtnXAZcE
    dOLkfcmgRQ6Vgi2aTmDY2JqJHnGZttJ8/bIZzqMIz8PMh/VSCQnYu01Os1UxB9Kf
    FaiPIdsDAgMBAAECggEAD8+FdeOgNlfaK+RNtyB4IKnH3PoKuJ06E63pAwKSKDHZ
    LyVi5SDdBftzZLtMuk/O8iBMIOxb70hD7LnOfCCjRkNa3DTvGt2R6ClLRJ+kPfxB
    LlZLNe/CLwdje6vkcYzAGmCBxhzgGmZSLzEl2En5WgZdza5ZOMsnIHqmAVXbWEcE
    o4rhAgk6pxoaNEcc+jt9rXRF907b+t7h83b6OR06ehCGk6W/StGgoljTIWxK7CDS
    FtPfwzs9L2tkUylBJ9pnMhMMCZnP0CWdi1nwEmRsSVHKm5DP5HiSM+hozykrRrtS
    BlFWH3OBDH7/GblvCewL0TGY/jHVESN8kM4/nI0ZKQKBgQDR2iYOOTXblALesITl
    /VlUS70/gZA0HS0cUgd3/PxaDo+apefl/aWwuF0/E5JWP7Hy9JNVDy3KssqcYhhK
    FueEoW1wcUJqtJGDtJAVShIVPEJ9yEFpgCWJPfMEp3OU4odOS/XfvijVyHHspuuf
    Bh9p/ESBlU+S+PMb6+5YZeOSaQKBgQDAJdYyZsACOGOScsPRsNjWZZoOf8PlrdNb
    VvnJMT+lJaXEEoQhdEHujlFEWKhc2RliyJlmY30H+nBOXd9AS1rIg8I9QwfnZt86
    SVFgw/tU53XuUbi42EdJQZBanJ0+lvrf1IQx+sPEG0J6yzrnby93iUmM3ZtHmaNJ
    +vpPwqL8iwKBgBQrbnrxfr6zFC+JMczVM+/JM9BVyKFpqHtPWw5qT2rseVr41Tgi
    z/kTT0sPu4H0r0rVvQ9w3QrdcmHjf8gnOWtjBJzJFgQhhNbu1OZm7yQBXbavN7JH
    MdRmEuSAn7hQqYaaAHDX2x7pHCINzRnEweIy7/awfix3Jw6o94ihimT5AoGALTB4
    2K+rlpoWaNnOzeEOjhWlDqXjt3+TBpdE9Zk8g6V//8XvB0MlQmp8GFvVdMimHMJa
    uWbKf/bZNMUE/UT7m87I/sll8XkTJM0bc2uED2rEJIFZtTdARK1Dutu8a3zskXmU
    gYCdS+CxWNm1B7rxaeaCwrtXipZKfdqlxd5boJMCgYEAtvCcH1+bEqa2/+LUPYEN
    StM0HFZUNsSmyeUlvdKipV1uPwPpQd0880ZvB2qaE5rpK2QYtag6zY0gWOYve07i
    xQDWmNTMnv3bzs3LdfAxnlsadoNdS7PyMZZ5bm/f1OswaBVb6MKpRnLO0aBZAb7h
    yp/u/UY5KasVLY7V3tgF9mc=
    -----END PRIVATE KEY-----
    """

private let testPublicKeyPEM = """
    -----BEGIN PUBLIC KEY-----
    MIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEAnYKgp9ecTKoTuEKHXKS8
    UCkdRhnd0c5pJMsVYWgVbs9GLq5M4F9YxxsUavbkc+ifUGM+BOIgoqvG/VzgxLfj
    KQ9bS9Eyo718a0ultv4bf4XuZQp4S0xz1zNoHlRBMwFUPFdofZBcvorousOqDfab
    irNF6Xlt64GuEgI8qtR2Jm3T3YbyOl0OUYSD8soPbU33wFc5SUtbLbQXKlW+4OO9
    9JpDAB2JMF6QHiuBn3UavjDkIigk0DzT1LFOCutuVJ8nUcDBtk7Z1wGXBHTi5H3J
    oEUOlYItmk5g2NiaiR5xmbbSfP2yGc6jCM/DzIf1UgkJ2LtNTrNVMQfSnxWojyHb
    AwIDAQAB
    -----END PUBLIC KEY-----
    """

private let testKeyPairId = "K2JCJMDEHXQW5F"

// Fixed date for deterministic tests: Jan 1, 2021 00:00:00 UTC
private let fixedDate = Date(timeIntervalSince1970: 1_609_459_200)

// MARK: - Test Suite

@Suite("CloudFrontSigner Tests")
struct CloudFrontSignerTests {

    // MARK: - Initializer Tests

    @Test("PEM and DER initializers produce identical signer behavior")
    func testBothInitializersProduceIdenticalBehavior() throws {
        let signerFromPEM = try CloudFrontSigner(
            keyPairId: testKeyPairId,
            privateKeyPEM: testPrivateKeyPEM
        )

        // Create DER representation from the same key
        let pemKey = try _RSA.Signing.PrivateKey(pemRepresentation: testPrivateKeyPEM)
        let derData = Data(pemKey.derRepresentation)
        let signerFromDER = try CloudFrontSigner(
            keyPairId: testKeyPairId,
            privateKeyDER: derData
        )

        // Both signers should produce identical signed URLs
        let url = "https://d111111abcdef8.cloudfront.net/image.jpg"
        let expires: TimeAmount = .hours(1)

        let signedURLFromPEM = try signerFromPEM.signedURL(url: url, policy: .canned(expires: expires), date: fixedDate)
        let signedURLFromDER = try signerFromDER.signedURL(url: url, policy: .canned(expires: expires), date: fixedDate)

        #expect(signedURLFromPEM == signedURLFromDER)
    }

    // MARK: - Canned Policy JSON Construction Tests

    @Test("Canned policy JSON matches AWS spec with no extra whitespace")
    func testCannedPolicyConstruction() throws {
        let signer = try CloudFrontSigner(
            keyPairId: testKeyPairId,
            privateKeyPEM: testPrivateKeyPEM
        )

        let resource = "https://d111111abcdef8.cloudfront.net/image.jpg"
        let epoch = 1_609_462_800  // Jan 1, 2021 01:00:00 UTC

        let policy = signer.cannedPolicyStatement(resource: resource, expiresEpoch: epoch)

        let expected =
            "{\"Statement\":[{\"Resource\":\"https://d111111abcdef8.cloudfront.net/image.jpg\",\"Condition\":{\"DateLessThan\":{\"AWS:EpochTime\":1609462800}}}]}"

        #expect(policy == expected)
        // Verify no whitespace
        #expect(!policy.contains(" "))
        #expect(!policy.contains("\n"))
        #expect(!policy.contains("\t"))
    }

    // MARK: - Custom Policy JSON Construction Tests

    @Test("Custom policy JSON with neither activeFrom nor ipAddress")
    func testCustomPolicyNeither() throws {
        let signer = try CloudFrontSigner(
            keyPairId: testKeyPairId,
            privateKeyPEM: testPrivateKeyPEM
        )

        let policy = signer.customPolicyStatement(
            resource: "https://d111111abcdef8.cloudfront.net/*",
            expiresEpoch: 1_609_462_800,
            activeFromEpoch: nil,
            ipAddress: nil
        )

        let expected =
            "{\"Statement\":[{\"Resource\":\"https://d111111abcdef8.cloudfront.net/*\",\"Condition\":{\"DateLessThan\":{\"AWS:EpochTime\":1609462800}}}]}"
        #expect(policy == expected)
    }

    @Test("Custom policy JSON with activeFrom only")
    func testCustomPolicyActiveFromOnly() throws {
        let signer = try CloudFrontSigner(
            keyPairId: testKeyPairId,
            privateKeyPEM: testPrivateKeyPEM
        )

        let policy = signer.customPolicyStatement(
            resource: "https://d111111abcdef8.cloudfront.net/*",
            expiresEpoch: 1_609_462_800,
            activeFromEpoch: 1_609_459_200,
            ipAddress: nil
        )

        let expected =
            "{\"Statement\":[{\"Resource\":\"https://d111111abcdef8.cloudfront.net/*\",\"Condition\":{\"DateLessThan\":{\"AWS:EpochTime\":1609462800},\"DateGreaterThan\":{\"AWS:EpochTime\":1609459200}}}]}"
        #expect(policy == expected)
    }

    @Test("Custom policy JSON with ipAddress only")
    func testCustomPolicyIpAddressOnly() throws {
        let signer = try CloudFrontSigner(
            keyPairId: testKeyPairId,
            privateKeyPEM: testPrivateKeyPEM
        )

        let policy = signer.customPolicyStatement(
            resource: "https://d111111abcdef8.cloudfront.net/*",
            expiresEpoch: 1_609_462_800,
            activeFromEpoch: nil,
            ipAddress: "192.0.2.0/24"
        )

        let expected =
            "{\"Statement\":[{\"Resource\":\"https://d111111abcdef8.cloudfront.net/*\",\"Condition\":{\"DateLessThan\":{\"AWS:EpochTime\":1609462800},\"IpAddress\":{\"AWS:SourceIp\":\"192.0.2.0/24\"}}}]}"
        #expect(policy == expected)
    }

    @Test("Custom policy JSON with both activeFrom and ipAddress")
    func testCustomPolicyBoth() throws {
        let signer = try CloudFrontSigner(
            keyPairId: testKeyPairId,
            privateKeyPEM: testPrivateKeyPEM
        )

        let policy = signer.customPolicyStatement(
            resource: "https://d111111abcdef8.cloudfront.net/*",
            expiresEpoch: 1_609_462_800,
            activeFromEpoch: 1_609_459_200,
            ipAddress: "192.0.2.0/24"
        )

        let expected =
            "{\"Statement\":[{\"Resource\":\"https://d111111abcdef8.cloudfront.net/*\",\"Condition\":{\"DateLessThan\":{\"AWS:EpochTime\":1609462800},\"DateGreaterThan\":{\"AWS:EpochTime\":1609459200},\"IpAddress\":{\"AWS:SourceIp\":\"192.0.2.0/24\"}}}]}"
        #expect(policy == expected)
    }

    // MARK: - CloudFront Base64 Encoding Tests

    @Test("CloudFront base64 encoding replaces + with -, = with _, / with ~")
    func testCloudFrontBase64Encoding() throws {
        // Create data that, when base64-encoded, contains +, /, and = characters
        // Standard base64 of bytes [0xFB, 0xFF, 0xBF] = "+/+/" (contains + and /)
        let data = Data([0xFB, 0xFF, 0xBF])
        let encoded = CloudFrontSigner.cloudFrontBase64Encode(data)

        // Standard base64 would be "u/+/" but let's verify no forbidden characters exist
        #expect(!encoded.contains("+"))
        #expect(!encoded.contains("="))
        #expect(!encoded.contains("/"))

        // Verify the substitutions are correct by checking against standard base64
        let standardBase64 = data.base64EncodedString()
        var expectedResult = ""
        for char in standardBase64 {
            switch char {
            case "+": expectedResult.append("-")
            case "=": expectedResult.append("_")
            case "/": expectedResult.append("~")
            default: expectedResult.append(char)
            }
        }
        #expect(encoded == expectedResult)
    }

    @Test("CloudFront base64 encoding handles padding characters correctly")
    func testCloudFrontBase64EncodingPadding() throws {
        // 1 byte → 2 base64 chars + 2 padding (==)
        let data1 = Data([0x41])  // "A" → standard base64: "QQ=="
        let encoded1 = CloudFrontSigner.cloudFrontBase64Encode(data1)
        #expect(encoded1 == "QQ__")
        #expect(!encoded1.contains("="))

        // 2 bytes → 3 base64 chars + 1 padding (=)
        let data2 = Data([0x41, 0x42])  // "AB" → standard base64: "QUI="
        let encoded2 = CloudFrontSigner.cloudFrontBase64Encode(data2)
        #expect(encoded2 == "QUI_")
        #expect(!encoded2.contains("="))
    }

    // MARK: - Signed URL Generation (Canned) Tests

    @Test("Signed URL (canned) contains Expires, Signature, Key-Pair-Id params")
    func testSignedURLCannedStructure() throws {
        let signer = try CloudFrontSigner(
            keyPairId: testKeyPairId,
            privateKeyPEM: testPrivateKeyPEM
        )

        let url = "https://d111111abcdef8.cloudfront.net/image.jpg"
        let signedURL = try signer.signedURL(url: url, policy: .canned(expires: .hours(1)), date: fixedDate)

        // Verify the signed URL starts with the original URL
        #expect(signedURL.hasPrefix(url))

        // Verify query parameters are present
        #expect(signedURL.contains("Expires="))
        #expect(signedURL.contains("Signature="))
        #expect(signedURL.contains("Key-Pair-Id=\(testKeyPairId)"))

        // Verify separator is ?
        let queryStart = signedURL.dropFirst(url.count)
        #expect(queryStart.hasPrefix("?"))

        // Verify the expiration value (1609459200 + 3600 = 1609462800)
        #expect(signedURL.contains("Expires=1609462800"))
    }

    // MARK: - Signed URL Generation (Custom) Tests

    @Test("Signed URL (custom) contains Policy, Signature, Key-Pair-Id params")
    func testSignedURLCustomStructure() throws {
        let signer = try CloudFrontSigner(
            keyPairId: testKeyPairId,
            privateKeyPEM: testPrivateKeyPEM
        )

        let url = "https://d111111abcdef8.cloudfront.net/video.mp4"
        let customPolicy = CloudFrontSigner.CustomPolicy(
            resource: "https://d111111abcdef8.cloudfront.net/*",
            expires: .hours(2)
        )

        let signedURL = try signer.signedURL(url: url, policy: .custom(customPolicy), date: fixedDate)

        // Verify the signed URL starts with the original URL
        #expect(signedURL.hasPrefix(url))

        // Verify query parameters are present
        #expect(signedURL.contains("Policy="))
        #expect(signedURL.contains("Signature="))
        #expect(signedURL.contains("Key-Pair-Id=\(testKeyPairId)"))

        // Custom policy should NOT have Expires param (uses Policy instead)
        #expect(!signedURL.contains("Expires="))
    }

    // MARK: - Custom Policy Resource Differs from URL

    @Test("Custom policy resource can differ from signed URL (wildcard vs specific file)")
    func testCustomPolicyResourceDiffersFromURL() throws {
        let signer = try CloudFrontSigner(
            keyPairId: testKeyPairId,
            privateKeyPEM: testPrivateKeyPEM
        )

        let specificURL = "https://d111111abcdef8.cloudfront.net/videos/movie.mp4"
        let wildcardResource = "https://d111111abcdef8.cloudfront.net/videos/*"

        let customPolicy = CloudFrontSigner.CustomPolicy(
            resource: wildcardResource,
            expires: .hours(1)
        )

        let signedURL = try signer.signedURL(url: specificURL, policy: .custom(customPolicy), date: fixedDate)

        // The signed URL should start with the specific URL, not the wildcard
        #expect(signedURL.hasPrefix(specificURL))

        // The policy embedded in the URL should contain the wildcard resource
        // Decode the policy parameter to verify
        #expect(signedURL.contains("Policy="))
    }

    // MARK: - SHA-256 Hash Algorithm Tests

    @Test("Signed URL with SHA-256 appends Hash-Algorithm=SHA256")
    func testSignedURLSHA256() throws {
        let signer = try CloudFrontSigner(
            keyPairId: testKeyPairId,
            privateKeyPEM: testPrivateKeyPEM,
            hashAlgorithm: .sha256
        )

        let url = "https://d111111abcdef8.cloudfront.net/image.jpg"
        let signedURL = try signer.signedURL(url: url, policy: .canned(expires: .hours(1)), date: fixedDate)

        #expect(signedURL.contains("Hash-Algorithm=SHA256"))
    }

    @Test("Signed URL with SHA-1 does NOT append Hash-Algorithm parameter")
    func testSignedURLSHA1NoHashAlgorithm() throws {
        let signer = try CloudFrontSigner(
            keyPairId: testKeyPairId,
            privateKeyPEM: testPrivateKeyPEM,
            hashAlgorithm: .sha1
        )

        let url = "https://d111111abcdef8.cloudfront.net/image.jpg"
        let signedURL = try signer.signedURL(url: url, policy: .canned(expires: .hours(1)), date: fixedDate)

        #expect(!signedURL.contains("Hash-Algorithm"))
    }

    // MARK: - Existing Query Parameters Tests

    @Test("Signed URL handles existing query parameters correctly (uses & not ?)")
    func testSignedURLWithExistingQueryParams() throws {
        let signer = try CloudFrontSigner(
            keyPairId: testKeyPairId,
            privateKeyPEM: testPrivateKeyPEM
        )

        let url = "https://d111111abcdef8.cloudfront.net/image.jpg?size=large&format=webp"
        let signedURL = try signer.signedURL(url: url, policy: .canned(expires: .hours(1)), date: fixedDate)

        // Should use & since URL already has query params
        #expect(signedURL.hasPrefix("https://d111111abcdef8.cloudfront.net/image.jpg?size=large&format=webp&"))
        #expect(signedURL.contains("&Expires="))
        #expect(signedURL.contains("&Signature="))
        #expect(signedURL.contains("&Key-Pair-Id="))
    }

    // MARK: - Signed Cookies (Canned) Tests

    @Test("Signed cookies (canned) contain expires, signature, keyPairId fields")
    func testSignedCookiesCanned() throws {
        let signer = try CloudFrontSigner(
            keyPairId: testKeyPairId,
            privateKeyPEM: testPrivateKeyPEM
        )

        let url = "https://d111111abcdef8.cloudfront.net/image.jpg"
        let cookies = try signer.signedCookies(url: url, policy: .canned(expires: .hours(1)), date: fixedDate)

        // Canned policy: has expires, no policy
        #expect(cookies.expires == 1_609_462_800)
        #expect(cookies.policy == nil)
        #expect(!cookies.signature.isEmpty)
        #expect(cookies.keyPairId == testKeyPairId)
    }

    // MARK: - Signed Cookies (Custom) Tests

    @Test("Signed cookies (custom) contain policy, signature, keyPairId fields")
    func testSignedCookiesCustom() throws {
        let signer = try CloudFrontSigner(
            keyPairId: testKeyPairId,
            privateKeyPEM: testPrivateKeyPEM
        )

        let customPolicy = CloudFrontSigner.CustomPolicy(
            resource: "https://d111111abcdef8.cloudfront.net/*",
            expires: .hours(2),
            ipAddress: "10.0.0.0/8"
        )

        let cookies = try signer.signedCookies(url: customPolicy.resource, policy: .custom(customPolicy), date: fixedDate)

        // Custom policy: has policy, no expires
        #expect(cookies.policy != nil)
        #expect(cookies.expires == nil)
        #expect(!cookies.signature.isEmpty)
        #expect(cookies.keyPairId == testKeyPairId)
        #expect(!cookies.policy!.isEmpty)
    }

    // MARK: - SignedCookies headerValues Tests

    @Test("Canned policy headerValues contains Expires, Signature, Key-Pair-Id")
    func testCannedCookiesHeaderValues() throws {
        let signer = try CloudFrontSigner(
            keyPairId: testKeyPairId,
            privateKeyPEM: testPrivateKeyPEM
        )

        let cookies = try signer.signedCookies(
            url: "https://d111111abcdef8.cloudfront.net/image.jpg",
            policy: .canned(expires: .hours(1)),
            date: fixedDate
        )

        let headers = cookies.headerValues
        #expect(headers.count == 3)
        #expect(headers[0] == "CloudFront-Expires=1609462800")
        #expect(headers[1].hasPrefix("CloudFront-Signature="))
        #expect(headers[2] == "CloudFront-Key-Pair-Id=\(testKeyPairId)")
    }

    @Test("Custom policy headerValues contains Policy, Signature, Key-Pair-Id")
    func testCustomCookiesHeaderValues() throws {
        let signer = try CloudFrontSigner(
            keyPairId: testKeyPairId,
            privateKeyPEM: testPrivateKeyPEM
        )

        let customPolicy = CloudFrontSigner.CustomPolicy(
            resource: "https://d111111abcdef8.cloudfront.net/*",
            expires: .hours(2)
        )

        let cookies = try signer.signedCookies(url: customPolicy.resource, policy: .custom(customPolicy), date: fixedDate)

        let headers = cookies.headerValues
        #expect(headers.count == 3)
        #expect(headers[0].hasPrefix("CloudFront-Policy="))
        #expect(headers[1].hasPrefix("CloudFront-Signature="))
        #expect(headers[2] == "CloudFront-Key-Pair-Id=\(testKeyPairId)")
    }

    // MARK: - Error Cases Tests

    @Test("Invalid PEM key data throws invalidPrivateKey")
    func testInvalidPEMKeyData() throws {
        #expect(throws: CloudFrontSignerError.invalidPrivateKey) {
            _ = try CloudFrontSigner(
                keyPairId: testKeyPairId,
                privateKeyPEM: "not a valid PEM key"
            )
        }
    }

    @Test("Malformed key throws invalidPrivateKey")
    func testMalformedKey() throws {
        let malformedPEM = """
            -----BEGIN PRIVATE KEY-----
            ThisIsNotValidBase64DataAtAll!!!
            -----END PRIVATE KEY-----
            """
        #expect(throws: CloudFrontSignerError.invalidPrivateKey) {
            _ = try CloudFrontSigner(
                keyPairId: testKeyPairId,
                privateKeyPEM: malformedPEM
            )
        }
    }

    @Test("Encrypted PEM key throws invalidPrivateKey")
    func testEncryptedPEMKey() throws {
        // An encrypted PEM header that _CryptoExtras cannot parse
        let encryptedPEM = """
            -----BEGIN ENCRYPTED PRIVATE KEY-----
            MIIFHDBOBgkqhkiG9w0BBQ0wQTApBgkqhkiG9w0BBQwwHAQIuBTTH7jHKHwCAggA
            MAwGCCqGSIb3DQIJBQAwFAYIKoZIhvcNAwcECOKcyrCY5XBJBIIEyJrXqkJBu3fZ
            -----END ENCRYPTED PRIVATE KEY-----
            """
        #expect(throws: CloudFrontSignerError.invalidPrivateKey) {
            _ = try CloudFrontSigner(
                keyPairId: testKeyPairId,
                privateKeyPEM: encryptedPEM
            )
        }
    }

    @Test("Invalid DER data throws invalidPrivateKey")
    func testInvalidDERData() throws {
        let invalidData = Data("garbage data".utf8)
        #expect(throws: CloudFrontSignerError.invalidPrivateKey) {
            _ = try CloudFrontSigner(
                keyPairId: testKeyPairId,
                privateKeyDER: invalidData
            )
        }
    }

    // MARK: - Edge Cases Tests

    @Test("URL with special characters in path")
    func testURLWithSpecialCharacters() throws {
        let signer = try CloudFrontSigner(
            keyPairId: testKeyPairId,
            privateKeyPEM: testPrivateKeyPEM
        )

        let url = "https://d111111abcdef8.cloudfront.net/path/with%20spaces/image%23file.jpg"
        let signedURL = try signer.signedURL(url: url, policy: .canned(expires: .hours(1)), date: fixedDate)

        #expect(signedURL.hasPrefix(url))
        #expect(signedURL.contains("Expires="))
        #expect(signedURL.contains("Signature="))
        #expect(signedURL.contains("Key-Pair-Id="))
    }

    @Test("Wildcard resource path")
    func testWildcardResourcePath() throws {
        let signer = try CloudFrontSigner(
            keyPairId: testKeyPairId,
            privateKeyPEM: testPrivateKeyPEM
        )

        let url = "https://d111111abcdef8.cloudfront.net/*"
        let signedURL = try signer.signedURL(url: url, policy: .canned(expires: .hours(1)), date: fixedDate)

        #expect(signedURL.hasPrefix("https://d111111abcdef8.cloudfront.net/*?"))
        #expect(signedURL.contains("Expires="))
    }

    @Test("Very long URL is handled correctly")
    func testVeryLongURL() throws {
        let signer = try CloudFrontSigner(
            keyPairId: testKeyPairId,
            privateKeyPEM: testPrivateKeyPEM
        )

        let longPath = String(repeating: "a", count: 2000)
        let url = "https://d111111abcdef8.cloudfront.net/\(longPath)"
        let signedURL = try signer.signedURL(url: url, policy: .canned(expires: .hours(1)), date: fixedDate)

        #expect(signedURL.hasPrefix(url))
        #expect(signedURL.contains("Expires="))
        #expect(signedURL.contains("Signature="))
        #expect(signedURL.contains("Key-Pair-Id="))
    }

    // MARK: - IP Address Passthrough Tests

    @Test("IPv4 CIDR value appears verbatim in policy JSON")
    func testIPv4CIDRPassthrough() throws {
        let signer = try CloudFrontSigner(
            keyPairId: testKeyPairId,
            privateKeyPEM: testPrivateKeyPEM
        )

        let cidr = "192.168.1.0/24"
        let policy = signer.customPolicyStatement(
            resource: "https://d111111abcdef8.cloudfront.net/*",
            expiresEpoch: 1_609_462_800,
            activeFromEpoch: nil,
            ipAddress: cidr
        )

        #expect(policy.contains("\"AWS:SourceIp\":\"192.168.1.0/24\""))
    }

    @Test("IPv6 CIDR value appears verbatim in policy JSON")
    func testIPv6CIDRPassthrough() throws {
        let signer = try CloudFrontSigner(
            keyPairId: testKeyPairId,
            privateKeyPEM: testPrivateKeyPEM
        )

        let cidr = "2001:db8::/32"
        let policy = signer.customPolicyStatement(
            resource: "https://d111111abcdef8.cloudfront.net/*",
            expiresEpoch: 1_609_462_800,
            activeFromEpoch: nil,
            ipAddress: cidr
        )

        #expect(policy.contains("\"AWS:SourceIp\":\"2001:db8::/32\""))
    }

    @Test("Single IPv4 with /32 suffix passes through verbatim")
    func testSingleIPv4Passthrough() throws {
        let signer = try CloudFrontSigner(
            keyPairId: testKeyPairId,
            privateKeyPEM: testPrivateKeyPEM
        )

        let ip = "203.0.113.1/32"
        let policy = signer.customPolicyStatement(
            resource: "https://d111111abcdef8.cloudfront.net/*",
            expiresEpoch: 1_609_462_800,
            activeFromEpoch: nil,
            ipAddress: ip
        )

        #expect(policy.contains("\"AWS:SourceIp\":\"203.0.113.1/32\""))
    }

    // MARK: - Deterministic Signature Tests

    @Test("Signature is deterministic (same inputs produce same output)")
    func testSignatureDeterminism() throws {
        let signer = try CloudFrontSigner(
            keyPairId: testKeyPairId,
            privateKeyPEM: testPrivateKeyPEM
        )

        let url = "https://d111111abcdef8.cloudfront.net/image.jpg"

        let signedURL1 = try signer.signedURL(url: url, policy: .canned(expires: .hours(1)), date: fixedDate)
        let signedURL2 = try signer.signedURL(url: url, policy: .canned(expires: .hours(1)), date: fixedDate)

        #expect(signedURL1 == signedURL2)
    }

    @Test("Signature is deterministic across multiple signer instances")
    func testSignatureDeterminismAcrossInstances() throws {
        let signer1 = try CloudFrontSigner(
            keyPairId: testKeyPairId,
            privateKeyPEM: testPrivateKeyPEM
        )
        let signer2 = try CloudFrontSigner(
            keyPairId: testKeyPairId,
            privateKeyPEM: testPrivateKeyPEM
        )

        let url = "https://d111111abcdef8.cloudfront.net/image.jpg"

        let signedURL1 = try signer1.signedURL(url: url, policy: .canned(expires: .hours(1)), date: fixedDate)
        let signedURL2 = try signer2.signedURL(url: url, policy: .canned(expires: .hours(1)), date: fixedDate)

        #expect(signedURL1 == signedURL2)
    }

    // MARK: - Signature Verification Tests

    @Test("Signature can be verified with corresponding public key (SHA-1)")
    func testSignatureVerificationSHA1() throws {
        let signer = try CloudFrontSigner(
            keyPairId: testKeyPairId,
            privateKeyPEM: testPrivateKeyPEM,
            hashAlgorithm: .sha1
        )

        // Sign some data
        let policyData: [UInt8] = Array("test policy data".utf8)
        let signatureData = try signer.sign(policyData)

        // Load public key and verify
        let publicKey = try _RSA.Signing.PublicKey(pemRepresentation: testPublicKeyPEM)
        let signature = _RSA.Signing.RSASignature(rawRepresentation: signatureData)

        let digest = Insecure.SHA1.hash(data: policyData)
        let isValid = publicKey.isValidSignature(signature, for: digest, padding: .insecurePKCS1v1_5)
        #expect(isValid)
    }

    @Test("Signature can be verified with corresponding public key (SHA-256)")
    func testSignatureVerificationSHA256() throws {
        let signer = try CloudFrontSigner(
            keyPairId: testKeyPairId,
            privateKeyPEM: testPrivateKeyPEM,
            hashAlgorithm: .sha256
        )

        // Sign some data
        let policyData: [UInt8] = Array("test policy data for sha256".utf8)
        let signatureData = try signer.sign(policyData)

        // Load public key and verify
        let publicKey = try _RSA.Signing.PublicKey(pemRepresentation: testPublicKeyPEM)
        let signature = _RSA.Signing.RSASignature(rawRepresentation: signatureData)

        let digest = SHA256.hash(data: policyData)
        let isValid = publicKey.isValidSignature(signature, for: digest, padding: .insecurePKCS1v1_5)
        #expect(isValid)
    }

    @Test("Signed URL signature can be verified with public key")
    func testSignedURLSignatureVerification() throws {
        let signer = try CloudFrontSigner(
            keyPairId: testKeyPairId,
            privateKeyPEM: testPrivateKeyPEM,
            hashAlgorithm: .sha1
        )

        let url = "https://d111111abcdef8.cloudfront.net/image.jpg"
        let epoch = Int(fixedDate.timeIntervalSince1970) + 3600

        // Get the policy that will be signed
        let policy = signer.cannedPolicyStatement(resource: url, expiresEpoch: epoch)

        // Sign the policy directly
        let signatureData = try signer.sign(Array(policy.utf8))

        // Verify with public key
        let publicKey = try _RSA.Signing.PublicKey(pemRepresentation: testPublicKeyPEM)
        let signature = _RSA.Signing.RSASignature(rawRepresentation: signatureData)

        let digest = Insecure.SHA1.hash(data: Array(policy.utf8))
        let isValid = publicKey.isValidSignature(signature, for: digest, padding: .insecurePKCS1v1_5)
        #expect(isValid)
    }

    // MARK: - Custom Policy SHA-256 URL Tests

    @Test("Custom policy signed URL with SHA-256 appends Hash-Algorithm=SHA256")
    func testCustomPolicySHA256() throws {
        let signer = try CloudFrontSigner(
            keyPairId: testKeyPairId,
            privateKeyPEM: testPrivateKeyPEM,
            hashAlgorithm: .sha256
        )

        let customPolicy = CloudFrontSigner.CustomPolicy(
            resource: "https://d111111abcdef8.cloudfront.net/*",
            expires: .hours(1)
        )

        let signedURL = try signer.signedURL(
            url: "https://d111111abcdef8.cloudfront.net/video.mp4",
            policy: .custom(customPolicy),
            date: fixedDate
        )

        #expect(signedURL.contains("Hash-Algorithm=SHA256"))
        #expect(signedURL.contains("Policy="))
        #expect(signedURL.contains("Signature="))
        #expect(signedURL.contains("Key-Pair-Id=\(testKeyPairId)"))
    }

    // MARK: - Custom Policy with existing query params

    @Test("Custom policy signed URL with existing query params uses &")
    func testCustomPolicyExistingQueryParams() throws {
        let signer = try CloudFrontSigner(
            keyPairId: testKeyPairId,
            privateKeyPEM: testPrivateKeyPEM
        )

        let url = "https://d111111abcdef8.cloudfront.net/video.mp4?quality=high"
        let customPolicy = CloudFrontSigner.CustomPolicy(
            resource: "https://d111111abcdef8.cloudfront.net/*",
            expires: .hours(1)
        )

        let signedURL = try signer.signedURL(url: url, policy: .custom(customPolicy), date: fixedDate)

        #expect(signedURL.hasPrefix("https://d111111abcdef8.cloudfront.net/video.mp4?quality=high&"))
        #expect(signedURL.contains("&Policy="))
    }
}
