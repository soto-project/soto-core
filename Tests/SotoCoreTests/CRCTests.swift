//===----------------------------------------------------------------------===//
//
// This source file is part of the Soto for AWS open source project
//
// Copyright (c) 2017-2022 the Soto project authors
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
import SotoCore
import SotoTestUtils
import XCTest

final class CRCTests: XCTestCase {
    func testCRC32() {
        XCTAssertEqual(soto_crc32(0, bytes: "".utf8), 0)
        XCTAssertEqual(soto_crc32(0, bytes: "a".utf8), 0xE8B7_BE43)
        XCTAssertEqual(soto_crc32(0, bytes: "abc".utf8), 0x3524_41C2)
        XCTAssertEqual(soto_crc32(0, bytes: "message digest".utf8), 0x2015_9D7F)
        XCTAssertEqual(soto_crc32(0, bytes: "abcdefghijklmnopqrstuvwxyz".utf8), 0x4C27_50BD)
    }

    func testCRC32C() {
        XCTAssertEqual(soto_crc32c(0, bytes: "".utf8), 0)
        XCTAssertEqual(soto_crc32c(0, bytes: "a".utf8), 0xC1D0_4330)
        XCTAssertEqual(soto_crc32c(0, bytes: "foo".utf8), 0xCFC4_AE1D)
        XCTAssertEqual(soto_crc32c(0, bytes: "hello world".utf8), 0xC994_65AA)
        XCTAssertEqual(soto_crc32c(0, bytes: [UInt8](repeating: 0, count: 32)), 0x8A91_36AA)
    }
}
