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

import SotoCore
import SotoTestUtils
import Testing

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif

final class CRCTests {
    @Test func testCRC32() {
        #expect(soto_crc32(0, bytes: "".utf8) == 0)
        #expect(soto_crc32(0, bytes: "a".utf8) == 0xE8B7_BE43)
        #expect(soto_crc32(0, bytes: "abc".utf8) == 0x3524_41C2)
        #expect(soto_crc32(0, bytes: "message digest".utf8) == 0x2015_9D7F)
        #expect(soto_crc32(0, bytes: "abcdefghijklmnopqrstuvwxyz".utf8) == 0x4C27_50BD)
    }

    @Test func testCRC32C() {
        #expect(soto_crc32c(0, bytes: "".utf8) == 0)
        #expect(soto_crc32c(0, bytes: "a".utf8) == 0xC1D0_4330)
        #expect(soto_crc32c(0, bytes: "foo".utf8) == 0xCFC4_AE1D)
        #expect(soto_crc32c(0, bytes: "hello world".utf8) == 0xC994_65AA)
        #expect(soto_crc32c(0, bytes: [UInt8](repeating: 0, count: 32)) == 0x8A91_36AA)
    }
}
