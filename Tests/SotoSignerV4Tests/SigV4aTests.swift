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

import SotoSignerV4
@_spi(SotoInternal) import SotoSignerV4
import Testing

final class SigV4aTests {

    @Test func testCompareConstantTime() {

        let lhs1: [UInt8] = [0x00, 0x00, 0x00]
        let rhs1: [UInt8] = [0x00, 0x00, 0x01]
        let lhs2: [UInt8] = [0xAB, 0xCD, 0x80, 0xFF, 0x01, 0x0A]
        let rhs2: [UInt8] = [0xAB, 0xCD, 0x80, 0xFF, 0x01, 0x0A]
        let lhs3: [UInt8] = [0xFF, 0xCD, 0x80, 0xFF, 0x01, 0x0A]
        let rhs3: [UInt8] = [0xFE, 0xCD, 0x80, 0xFF, 0x01, 0x0A]

        #expect(SigV4aKeyPair.compareConstantTime(lhs: lhs1, rhs: rhs1) == -1)
        #expect(SigV4aKeyPair.compareConstantTime(lhs: lhs2, rhs: rhs2) == 0)
        #expect(SigV4aKeyPair.compareConstantTime(lhs: lhs3, rhs: rhs3) == 1)

    }

    @Test func testAddOne() {
        #expect([0x00, 0x00, 0x00].addingOne() == [0x00, 0x00, 0x01])
        #expect([0x00, 0x00, 0xFF].addingOne() == [0x00, 0x01, 0x00])
        #expect([0x00, 0xFF, 0xFF].addingOne() == [0x01, 0x00, 0x00])
        #expect([0xFF, 0xFF, 0xFF, 0xFF].addingOne() == [0x00, 0x00, 0x00, 0x00])
    }

    @Test func testDerivedStaticKey() {
        let accessKey = "AKISORANDOMAASORANDOM"
        let secretAccessKey = "q+jcrXGc+0zWN6uzclKVhvMmUsIfRPa4rlRandom"

        let expectedPrivateKeyHex = "7fd3bd010c0d9c292141c2b77bfbde1042c92e6836fff749d1269ec890fca1bd"

        let credential = StaticCredential(accessKeyId: accessKey, secretAccessKey: secretAccessKey)

        let result = SigV4aKeyPair(credential: credential)
        #expect(result.key.rawRepresentation.hexDigest() == expectedPrivateKeyHex)
    }

    @Test func testDeriveLongKey() {
        let accessKey = """
            AKISORANDOMAASORANDOMFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF\
            FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF\
            FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFf
            """
        let secretAccessKey = "q+jcrXGc+0zWN6uzclKVhvMmUsIfRPa4rlRandom"

        let expectedPrivateKeyHex = "bc0fd68955922f2cccd5c27f8aa04394a467ef1076d889b66569c6d2e764faf3"

        let credential = StaticCredential(accessKeyId: accessKey, secretAccessKey: secretAccessKey)

        let result = SigV4aKeyPair(credential: credential)
        #expect(result.key.rawRepresentation.hexDigest() == expectedPrivateKeyHex)
        #expect(String(decoding: HexEncoding(result.key.rawRepresentation), as: Unicode.UTF8.self) == expectedPrivateKeyHex)
    }

    @Test func testHexEncoding() {
        #expect(String(decoding: HexEncoding([0]), as: Unicode.UTF8.self) == "00")
        #expect(String(decoding: HexEncoding([1]), as: Unicode.UTF8.self) == "01")
        #expect(String(decoding: HexEncoding([254]), as: Unicode.UTF8.self) == "fe")
        #expect(String(decoding: HexEncoding([255]), as: Unicode.UTF8.self) == "ff")
        #expect(String(decoding: HexEncoding([254, 255, 0]), as: Unicode.UTF8.self) == "feff00")
    }
}
