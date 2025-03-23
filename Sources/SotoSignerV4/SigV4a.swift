//===----------------------------------------------------------------------===//
//
// This source file is part of the Soto for AWS open source project
//
// Copyright (c) 2025 the Soto project authors
// Licensed under Apache License v2.0
//
// See LICENSE.txt for license information
// See CONTRIBUTORS.txt for the list of Soto project authors
//
// SPDX-License-Identifier: Apache-2.0
//
//===----------------------------------------------------------------------===//

import Crypto
#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import struct Foundation.Data
#endif

package struct SigV4aKeyPair {

    package let key: P256.Signing.PrivateKey

    package init(credential: some Credential) {
        let secretBuffer = Self.makeSecretBuffer(credential: credential)
        let secretKey = SymmetricKey(data: secretBuffer)

        var inputBuffer = Self.makeFixedInputBuffer(credential: credential, counter: 1)

        for counter in Self.KEY_DERIVATION_COUNTER_RANGE {

            // We reuse the once created buffer here over and over by just changing the counter
            // value.
            inputBuffer[inputBuffer.index(inputBuffer.endIndex, offsetBy: -5)] = counter

            let digest = HMAC<SHA256>.authenticationCode(for: inputBuffer, using: secretKey)

            let digestAsArray = [UInt8](digest)

            switch try! Self.makeDerivedKey(bytes: digestAsArray) {
            case .nextCounter:
                continue

            case .success(let key):
                self.key = key
                return
            }
        }

        fatalError("Throw error here")
    }

    package func sign(_ string: String) throws -> String {
        // we want to be explcit about using SHA256 as the hash method
        let digest = SHA256.hash(data: Data(string.utf8))
        let signature = try self.key.signature(for: digest)

        return signature.derRepresentation.withUnsafeBytes {
            String(decoding: HexEncoding($0), as: Unicode.UTF8.self)
        }
    }

    private static var KEY_DERIVATION_COUNTER_RANGE: ClosedRange<UInt8> { 1...254 }

    static func makeFixedInputBuffer(credential: some Credential, counter: UInt8) -> [UInt8] {
        guard Self.KEY_DERIVATION_COUNTER_RANGE.contains(counter) else {
            fatalError("counter must be in range: \(Self.KEY_DERIVATION_COUNTER_RANGE)")
        }

        var result = [UInt8]()
        result.reserveCapacity(32 + credential.accessKeyId.utf8.count)
        result.append(contentsOf: [0, 0, 0, 1])
        result.append(contentsOf: "AWS4-ECDSA-P256-SHA256".utf8)
        result.append(0)
        result.append(contentsOf: credential.accessKeyId.utf8)
        result.append(counter)
        result.append(contentsOf: [0, 0, 1, 0])

        return result
    }

    private static let SECRET_BUFFER_PREFIX = "AWS4A"

    static func makeSecretBuffer(credential: some Credential) -> [UInt8] {
        var result = [UInt8]()
        result.reserveCapacity(credential.secretAccessKey.utf8.count + self.SECRET_BUFFER_PREFIX.utf8.count)
        result.append(contentsOf: self.SECRET_BUFFER_PREFIX.utf8)
        result.append(contentsOf: credential.secretAccessKey.utf8)
        return result
    }

    package static func compareConstantTime(lhs: [UInt8], rhs: [UInt8]) -> Int8 {
        guard lhs.count == rhs.count else {
            fatalError("Input arrays must be of same size")
        }

        var gt: UInt8 = 0
        var eq: UInt8 = 1
        let length = lhs.count

        for i in 0..<length {
            let lhsDigit: Int32 = Int32(lhs[i])
            let rhsDigit: Int32 = Int32(rhs[i])

            gt |= UInt8(bitPattern: Int8((rhsDigit - lhsDigit) >> 31)) & eq
            eq &= UInt8(bitPattern: Int8((((lhsDigit ^ rhsDigit) - 1) >> 31) & 0x01))
        }

        return Int8(gt) + Int8(gt) + Int8(eq) - 1
    }

    package enum DerivedKeyResult {
        case success(P256.Signing.PrivateKey)
        case nextCounter
    }

    private static let s_n_minus_2: [UInt8] = [
        0xFF, 0xFF, 0xFF, 0xFF, 0x00, 0x00, 0x00, 0x00,
        0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF,
        0xBC, 0xE6, 0xFA, 0xAD, 0xA7, 0x17, 0x9E, 0x84,
        0xF3, 0xB9, 0xCA, 0xC2, 0xFC, 0x63, 0x25, 0x4F,
    ]

    package static func makeDerivedKey(bytes: [UInt8]) throws -> DerivedKeyResult {
        assert(bytes.count == 32)

        let comparisonResult = Self.compareConstantTime(lhs: bytes, rhs: Self.s_n_minus_2)
        if comparisonResult > 0 {
            return .nextCounter
        }

        return try .success(P256.Signing.PrivateKey(rawRepresentation: bytes.addingOne()))
    }
}

extension [UInt8] {

    fileprivate mutating func addOne() {
        var carry: UInt32 = 1
        for index in self.indices.reversed() {
            var digit = UInt32(self[index])
            digit += carry
            carry = (digit >> 8) & 0x01
            self[index] = UInt8(digit & 0xFF)

            // once carry is we will not have any further changes and we can exit early
            if carry == 0 { return }
        }
    }

    package consuming func addingOne() -> [UInt8] {
        var new = consume self
        new.addOne()
        return new
    }
}
