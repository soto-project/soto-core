//===----------------------------------------------------------------------===//
//
// This source file is part of the Soto for AWS open source project
//
// Copyright (c) 2026 the Soto project authors
// Licensed under Apache License v2.0
//
// See LICENSE.txt for license information
// See CONTRIBUTORS.txt for the list of Soto project authors
//
// SPDX-License-Identifier: Apache-2.0
//
//===----------------------------------------------------------------------===//

import NIOCore
import Testing

import struct Foundation.Data
import struct Foundation.Date

@testable import SotoCore

/// Convert a hex string such as "1a 000f4240" to bytes
private func hex(_ string: String) -> [UInt8] {
    let digits = Array(string.filter { !$0.isWhitespace })
    precondition(digits.count % 2 == 0)
    return stride(from: 0, to: digits.count, by: 2).map {
        UInt8(String(digits[$0..<$0 + 2]), radix: 16)!
    }
}

private func encode(_ value: some Encodable) throws -> [UInt8] {
    try CBOREncoder().encode(value)
}

private func decode<T: Decodable>(_ type: T.Type = T.self, _ hexString: String) throws -> T {
    try CBORDecoder().decode(type, from: hex(hexString))
}

/// Decodable that ignores its input, used to check the parser on its own
private struct Ignored: Decodable {
    init(from decoder: any Decoder) throws {}
}

@Suite("CBOR coder")
struct CBORCoderTests {
    // MARK: RFC 8949 Appendix A

    static let unsignedVectors: [(String, UInt64)] = [
        ("00", 0),
        ("01", 1),
        ("0a", 10),
        ("17", 23),
        ("1818", 24),
        ("1819", 25),
        ("1864", 100),
        ("1903e8", 1000),
        ("1a000f4240", 1_000_000),
        ("1b000000e8d4a51000", 1_000_000_000_000),
        ("1bffffffffffffffff", 18_446_744_073_709_551_615),
    ]

    @Test("Unsigned integers encode in the shortest form", arguments: unsignedVectors)
    func encodeUnsigned(hexString: String, value: UInt64) throws {
        #expect(try encode(value) == hex(hexString))
    }

    @Test("Unsigned integers decode", arguments: unsignedVectors)
    func decodeUnsigned(hexString: String, value: UInt64) throws {
        #expect(try decode(UInt64.self, hexString) == value)
    }

    static let negativeVectors: [(String, Int64)] = [
        ("20", -1),
        ("29", -10),
        ("3863", -100),
        ("3903e7", -1000),
        ("3b7fffffffffffffff", Int64.min),
    ]

    @Test("Negative integers encode in the shortest form", arguments: negativeVectors)
    func encodeNegative(hexString: String, value: Int64) throws {
        #expect(try encode(value) == hex(hexString))
    }

    @Test("Negative integers decode", arguments: negativeVectors)
    func decodeNegative(hexString: String, value: Int64) throws {
        #expect(try decode(Int64.self, hexString) == value)
    }

    @Test("Integer widths")
    func integerWidths() throws {
        #expect(try encode(Int8(-5)) == hex("24"))
        #expect(try encode(UInt8(255)) == hex("18ff"))
        #expect(try encode(Int16.max) == hex("197fff"))
        #expect(try encode(UInt16.max) == hex("19ffff"))
        #expect(try encode(Int32.min) == hex("3a7fffffff"))
        #expect(try encode(UInt32.max) == hex("1affffffff"))
        #expect(try encode(Int.max) == hex("1b7fffffffffffffff"))
        #expect(try encode(UInt.max) == hex("1bffffffffffffffff"))
    }

    @Test("Integer too large for the requested type throws")
    func integerOutOfRange() {
        #expect(throws: DecodingError.self) { try decode(Int64.self, "3bffffffffffffffff") }  // -18446744073709551616
        #expect(throws: DecodingError.self) { try decode(Int64.self, "1bffffffffffffffff") }
        #expect(throws: DecodingError.self) { try decode(UInt8.self, "190100") }
        #expect(throws: DecodingError.self) { try decode(UInt8.self, "20") }
        #expect(throws: DecodingError.self) { try decode(Int8.self, "3881") }
    }

    static let floatDecodeVectors: [(String, Double)] = [
        ("f90000", 0.0),
        ("f93c00", 1.0),
        ("fb3ff199999999999a", 1.1),
        ("f93e00", 1.5),
        ("f97bff", 65504.0),
        ("fa47c35000", 100000.0),
        ("fa7f7fffff", 3.4028234663852886e+38),
        ("fb7e37e43c8800759c", 1.0e+300),
        ("f90001", 5.960464477539063e-8),
        ("f90400", 0.00006103515625),
        ("f9c400", -4.0),
        ("fbc010666666666666", -4.1),
        ("f97c00", .infinity),
        ("f9fc00", -.infinity),
        ("fa7f800000", .infinity),
        ("fb7ff0000000000000", .infinity),
        ("f98000", -0.0),
    ]

    @Test("Floats decode from half, single and double precision", arguments: floatDecodeVectors)
    func decodeFloat(hexString: String, value: Double) throws {
        let decoded = try decode(Double.self, hexString)
        #expect(decoded == value)
        #expect(decoded.sign == value.sign)
    }

    @Test("NaN decodes")
    func decodeNaN() throws {
        #expect(try decode(Double.self, "f97e00").isNaN)
        #expect(try decode(Double.self, "fa7fc00000").isNaN)
        #expect(try decode(Double.self, "fb7ff8000000000000").isNaN)
    }

    @Test("Integers decode as floating point")
    func integerAsDouble() throws {
        #expect(try decode(Double.self, "1903e8") == 1000)
        #expect(try decode(Double.self, "3863") == -100)
        #expect(try decode(Float.self, "01") == 1)
    }

    @Test("Doubles encode as 64 bit floats")
    func encodeDouble() throws {
        #expect(try encode(1.1) == hex("fb3ff199999999999a"))
        #expect(try encode(1.0e+300) == hex("fb7e37e43c8800759c"))
        #expect(try encode(-4.1) == hex("fbc010666666666666"))
        #expect(try encode(Double.infinity) == hex("fb7ff0000000000000"))
        #expect(try decode(Double.self, "fb7ff8000000000000").isNaN)
        #expect(try encode(Double.nan).count == 9)
    }

    @Test("Floats encode as 32 bit floats")
    func encodeFloat() throws {
        #expect(try encode(Float(100000.0)) == hex("fa47c35000"))
        #expect(try encode(Float(3.4028234663852886e+38)) == hex("fa7f7fffff"))
        #expect(try decode(Float.self, "fa47c35000") == 100000.0)
    }

    @Test("Simple values")
    func simpleValues() throws {
        #expect(try encode(false) == hex("f4"))
        #expect(try encode(true) == hex("f5"))
        #expect(try encode(String?.none) == hex("f6"))
        #expect(try decode(Bool.self, "f4") == false)
        #expect(try decode(Bool.self, "f5") == true)
        #expect(try decode(String?.self, "f6") == nil)
        // undefined decodes as null
        #expect(try decode(String?.self, "f7") == nil)
    }

    static let textVectors: [(String, String)] = [
        ("60", ""),
        ("6161", "a"),
        ("6449455446", "IETF"),
        ("62225c", "\"\\"),
        ("62c3bc", "\u{00fc}"),
        ("63e6b0b4", "\u{6c34}"),
        ("64f0908591", "\u{10151}"),
    ]

    @Test("Text strings encode", arguments: textVectors)
    func encodeText(hexString: String, value: String) throws {
        #expect(try encode(value) == hex(hexString))
    }

    @Test("Text strings decode", arguments: textVectors)
    func decodeText(hexString: String, value: String) throws {
        #expect(try decode(String.self, hexString) == value)
    }

    @Test("Byte strings")
    func byteStrings() throws {
        #expect(try encode([UInt8]()) == hex("40"))
        #expect(try encode([UInt8]([1, 2, 3, 4])) == hex("44 01020304"))
        #expect(try encode(Data([1, 2, 3, 4])) == hex("44 01020304"))
        #expect(try decode([UInt8].self, "40") == [])
        #expect(try decode([UInt8].self, "44 01020304") == [1, 2, 3, 4])
        #expect(try decode(Data.self, "44 01020304") == Data([1, 2, 3, 4]))
    }

    @Test("An array of small integers is still decodable as bytes")
    func arrayAsBytes() throws {
        #expect(try decode([UInt8].self, "83 010203") == [1, 2, 3])
        #expect(try decode(Data.self, "83 010203") == Data([1, 2, 3]))
    }

    @Test("Empty arrays of other element types are not byte strings")
    func emptyArrays() throws {
        #expect(try encode([String]()) == hex("80"))
        #expect(try encode([[String]]()) == hex("80"))
        #expect(try encode([[String]]([[], []])) == hex("82 80 80"))
        #expect(try encode([Data]()) == hex("80"))
    }

    @Test("Arrays")
    func arrays() throws {
        #expect(try encode([Int]()) == hex("80"))
        #expect(try encode([1, 2, 3]) == hex("83010203"))
        #expect(try encode([[1], [2, 3], [4, 5]]) == hex("83 81 01 82 0203 82 0405"))
        #expect(try decode([Int].self, "80") == [])
        #expect(try decode([Int].self, "83010203") == [1, 2, 3])
        #expect(try decode([[Int]].self, "83 81 01 82 0203 82 0405") == [[1], [2, 3], [4, 5]])
        let twentyFive = Array(1...25)
        let encoded = hex("98 19 0102030405060708090a0b0c0d0e0f101112131415161718 18 18 19")
        #expect(try encode(twentyFive) == encoded)
        #expect(try decode([Int].self, "98 19 0102030405060708090a0b0c0d0e0f101112131415161718 18 18 19") == twentyFive)
    }

    @Test("Maps")
    func maps() throws {
        #expect(try encode([String: Int]()) == hex("a0"))
        #expect(try encode(["a": 1]) == hex("a1 6161 01"))
        #expect(try encode(["a": [2, 3]]) == hex("a1 6161 82 0203"))
        #expect(try decode([String: Int].self, "a0") == [:])
        #expect(try decode([String: [Int]].self, "a2 6161 81 01 6162 82 0203") == ["a": [1], "b": [2, 3]])
        #expect(
            try decode([String: String].self, "a5 6161 6141 6162 6142 6163 6143 6164 6144 6165 6145") == [
                "a": "A", "b": "B", "c": "C", "d": "D", "e": "E",
            ]
        )
        #expect(try decode([[String: String]].self, "81 a1 6162 6163") == [["b": "c"]])
    }

    @Test("Integer map keys decode as strings")
    func integerMapKeys() throws {
        #expect(try decode([Int: String].self, "a2 01 6161 20 6162") == [1: "a", -1: "b"])
    }

    // MARK: Indefinite length

    @Test("Indefinite length items decode")
    func indefiniteLength() throws {
        #expect(try decode([UInt8].self, "5f 420102 43030405 ff") == [1, 2, 3, 4, 5])
        #expect(try decode(String.self, "7f 65 7374726561 64 6d696e67 ff") == "streaming")
        #expect(try decode([Int].self, "9fff") == [])
        #expect(try decode([Int].self, "9f010203ff") == [1, 2, 3])
        #expect(try decode([[Int]].self, "9f 81 01 82 0203 9f 0405 ff ff") == [[1], [2, 3], [4, 5]])
        #expect(try decode([[Int]].self, "83 81 01 82 0203 9f 0405 ff") == [[1], [2, 3], [4, 5]])
        #expect(try decode([String: [Int]].self, "bf 6161 81 01 6162 9f 0203 ff ff") == ["a": [1], "b": [2, 3]])
        #expect(try decode([String: Bool].self, "bf 63 46756e f5 ff") == ["Fun": true])
        #expect(try decode([String: Int].self, "bf 6341 6d74 21 ff") == ["Amt": -2])
        #expect(try decode([[String: String]].self, "81 bf 6162 6163 ff") == [["b": "c"]])
    }

    // MARK: Tags

    @Test("Tag 1 decodes integer and float dates")
    func decodeDate() throws {
        #expect(try decode(Date.self, "c1 1a514b67b0") == Date(timeIntervalSince1970: 1_363_896_240))
        #expect(try decode(Date.self, "c1 fb41d452d9ec200000") == Date(timeIntervalSince1970: 1_363_896_240.5))
        #expect(try decode(Date.self, "c1 f93e00") == Date(timeIntervalSince1970: 1.5))
        #expect(try decode(Date.self, "c1 20") == Date(timeIntervalSince1970: -1))
        // an untagged number is also accepted
        #expect(try decode(Date.self, "1a514b67b0") == Date(timeIntervalSince1970: 1_363_896_240))
    }

    @Test("Tag 1 containing anything else throws")
    func badDate() {
        #expect(throws: CBORError.self) { try decode(Date.self, "c1 6161") }
        #expect(throws: DecodingError.self) { try decode(Date.self, "6161") }
    }

    @Test("Dates encode as tag 1")
    func encodeDate() throws {
        #expect(try encode(Date(timeIntervalSince1970: 1_363_896_240)) == hex("c1 1a514b67b0"))
        #expect(try encode(Date(timeIntervalSince1970: 1_363_896_240.5)) == hex("c1 fb41d452d9ec200000"))
        #expect(try encode(Date(timeIntervalSince1970: -1)) == hex("c1 20"))
        #expect(try encode(Date(timeIntervalSince1970: 0)) == hex("c1 00"))
    }

    @Test("Other tags are skipped")
    func skippedTags() throws {
        #expect(try decode(String.self, "c0 74 323031332d30332d32315432303a30343a30305a") == "2013-03-21T20:04:00Z")
        #expect(try decode(String.self, "d820 76 687474703a2f2f7777772e6578616d706c652e636f6d") == "http://www.example.com")
        #expect(try decode([UInt8].self, "d818 45 6449455446") == hex("6449455446"))
        #expect(try decode(Int.self, "c2 c3 05") == 5)
    }

    // MARK: Errors

    @Test(
        "Truncated input throws",
        arguments: [
            "",
            "18",
            "19 01",
            "1a 0102",
            "1b 01020304050607",
            "62 61",
            "44 010203",
            "83 01 02",
            "a1 61 61",
            "a1 6161",
            "9f 01",
            "bf 6161 01",
            "5f 41 01",
            "7f 61 61",
            "c1",
            "f9 00",
            "fa 000000",
            "fb 00000000000000",
            "9b ffffffffffffffff",
            "bb 7fffffffffffffff",
            "5b ffffffffffffffff",
            "7a ffffffff 61",
        ]
    )
    func truncated(hexString: String) {
        #expect(throws: CBORError.truncatedInput) { try decode(Ignored.self, hexString) }
    }

    @Test("Trailing bytes throw")
    func trailingData() {
        #expect(throws: CBORError.trailingData) { try decode(Int.self, "00 00") }
        #expect(throws: CBORError.trailingData) { try decode([Int].self, "80 ff") }
    }

    @Test(
        "Malformed input throws",
        arguments: [
            "1c",  // reserved additional information
            "1d",
            "1e",
            "ff",  // unexpected break
            "81 ff",
            "a1 ff",
            "f8 20",  // simple value in following byte
            "f0",  // unassigned simple value
            "62 c328",  // invalid utf-8
            "7f 41 61 ff",  // byte string chunk inside a text string
            "5f 61 61 ff",  // text chunk inside a byte string
            "5f 5f ff ff",  // nested indefinite string
            "5f 1f ff",
            "c1 80",  // date tag on an array
        ]
    )
    func malformed(hexString: String) {
        do {
            _ = try decode(Ignored.self, hexString)
            Issue.record("Expected \(hexString) to throw")
        } catch let error as CBORError {
            guard case .malformed = error else {
                Issue.record("Unexpected error \(error) for \(hexString)")
                return
            }
        } catch {
            Issue.record("Unexpected error \(error) for \(hexString)")
        }
    }

    @Test("Deeply nested arrays throw instead of overflowing the stack")
    func nestedArrays() throws {
        let ok = [UInt8](repeating: 0x81, count: 100) + [0x00]
        _ = try CBORDecoder().decode(Ignored.self, from: ok)

        let tooDeep = [UInt8](repeating: 0x81, count: 100_000) + [0x00]
        #expect(throws: CBORError.nestingTooDeep) { try CBORDecoder().decode(Ignored.self, from: tooDeep) }
    }

    @Test("Deeply nested maps, tags and indefinite arrays throw")
    func nestedOther() {
        var maps: [UInt8] = []
        for _ in 0..<1000 { maps += [0xa1, 0x61, 0x61] }
        maps.append(0x00)
        #expect(throws: CBORError.nestingTooDeep) { try CBORDecoder().decode(Ignored.self, from: maps) }

        let tags = [UInt8](repeating: 0xc6, count: 100_000) + [0x00]
        #expect(throws: CBORError.nestingTooDeep) { try CBORDecoder().decode(Ignored.self, from: tags) }

        let indefinite = [UInt8](repeating: 0x9f, count: 100_000)
        #expect(throws: CBORError.nestingTooDeep) { try CBORDecoder().decode(Ignored.self, from: indefinite) }
    }

    @Test("Type mismatches throw DecodingError")
    func typeMismatch() {
        #expect(throws: DecodingError.self) { try decode(String.self, "01") }
        #expect(throws: DecodingError.self) { try decode(Int.self, "6161") }
        #expect(throws: DecodingError.self) { try decode(Bool.self, "01") }
        #expect(throws: DecodingError.self) { try decode([Int].self, "a0") }
        #expect(throws: DecodingError.self) { try decode([String: Int].self, "80") }
        #expect(throws: DecodingError.self) { try decode(Double.self, "6161") }
        #expect(throws: DecodingError.self) { try decode(Data.self, "6161") }
        #expect(throws: DecodingError.self) { try decode([String: Int].self, "a1 f4 00") }  // bool key
    }

    @Test("A missing key throws keyNotFound")
    func missingKey() {
        struct Required: Decodable { let name: String }
        #expect {
            try decode(Required.self, "a0")
        } throws: { error in
            guard case DecodingError.keyNotFound(let key, _) = error else { return false }
            return key.stringValue == "name"
        }
    }

    // MARK: Codable

    struct Address: Codable, Equatable {
        let street: String
        let postcode: String?
    }

    enum Colour: String, Codable {
        case red
        case green
    }

    struct Shape: Codable, Equatable {
        let name: String
        let count: Int
        let small: Int8
        let big: UInt64
        let negative: Int64
        let ratio: Double
        let single: Float
        let enabled: Bool
        let optional: String?
        let missing: Int?
        let address: Address
        let addresses: [Address]
        let numbers: [Int]
        let nested: [[String]]
        let lookup: [String: Int]
        let nestedLookup: [String: [String: Address]]
        let date: Date
        let optionalDate: Date?
        let dates: [Date]
        let blob: Data
        let blobs: [Data]
        let bytes: [UInt8]
        let colour: Colour
        let colours: [Colour: Int]
        let url: String
    }

    static let shape = Shape(
        name: "shape",
        count: 42,
        small: -8,
        big: UInt64.max,
        negative: Int64.min,
        ratio: 0.1,
        single: 1.5,
        enabled: true,
        optional: "yes",
        missing: nil,
        address: .init(street: "1 Road", postcode: nil),
        addresses: [.init(street: "2 Road", postcode: "AB1"), .init(street: "3 Road", postcode: nil)],
        numbers: [1, -2, 300, 70000, 5_000_000_000],
        nested: [["a", "b"], [], ["c"]],
        lookup: ["one": 1, "two": 2, "three": 3],
        nestedLookup: ["x": ["y": .init(street: "deep", postcode: "Z")]],
        date: Date(timeIntervalSince1970: 1_363_896_240),
        optionalDate: Date(timeIntervalSince1970: 1_363_896_240.25),
        dates: [Date(timeIntervalSince1970: 0), Date(timeIntervalSince1970: -86400.5)],
        blob: Data([0, 1, 2, 255]),
        blobs: [Data(), Data([9])],
        bytes: [7, 8, 9],
        colour: .green,
        colours: [.red: 1],
        url: "https://example.com/a?b=c"
    )

    @Test("A Codable struct round trips")
    func roundTripStruct() throws {
        let encoded = try CBOREncoder().encode(Self.shape)
        let decoded = try CBORDecoder().decode(Shape.self, from: encoded)
        #expect(decoded == Self.shape)
    }

    @Test("Round trip through a ByteBuffer")
    func roundTripByteBuffer() throws {
        let buffer = try CBOREncoder().encodeAsByteBuffer(Self.shape, allocator: ByteBufferAllocator())
        #expect(try CBORDecoder().decode(Shape.self, from: buffer) == Self.shape)
        #expect(Array(buffer.readableBytesView) == (try encode(Self.shape)))
    }

    @Test("Decoding from a ByteBuffer slice uses the readable bytes only")
    func byteBufferSlice() throws {
        var buffer = ByteBuffer(bytes: [0xff, 0xff] + hex("83010203"))
        buffer.moveReaderIndex(forwardBy: 2)
        #expect(try CBORDecoder().decode([Int].self, from: buffer) == [1, 2, 3])
    }

    @Test("Structs encode as maps with string keys, and nil optionals are left out")
    func structLayout() throws {
        #expect(try encode(Address(street: "a", postcode: nil)) == hex("a1 66 737472656574 61 61"))
        #expect(try encode(Address(street: "a", postcode: "b")).count == 1 + 7 + 2 + 9 + 2)
        let decoded = try decode(Address.self, "a1 66 737472656574 61 61")
        #expect(decoded == Address(street: "a", postcode: nil))
        // an explicit null decodes as nil too
        let withNull = try decode(Address.self, "a2 66 737472656574 61 61 68 706f7374636f6465 f6")
        #expect(withNull == Address(street: "a", postcode: nil))
    }

    @Test("Unknown keys are ignored")
    func unknownKeys() throws {
        let decoded = try decode(Address.self, "a2 66 737472656574 61 61 65 6f74686572 83 010203")
        #expect(decoded == Address(street: "a", postcode: nil))
    }

    @Test("Decoded arrays of structs keep their order")
    func arrayOrder() throws {
        let addresses = (0..<50).map { Address(street: "street \($0)", postcode: $0 % 2 == 0 ? "p\($0)" : nil) }
        let bytes = try encode(addresses)
        #expect(try CBORDecoder().decode([Address].self, from: bytes) == addresses)
    }

    @Test("Large collections")
    func largeCollections() throws {
        let numbers = Array(0..<100_000)
        #expect(try CBORDecoder().decode([Int].self, from: encode(numbers)) == numbers)
        let blob = [UInt8](repeating: 0xab, count: 70_000)
        let encoded = try encode(blob)
        #expect(encoded.prefix(5) == [0x5a, 0x00, 0x01, 0x11, 0x70])
        #expect(try CBORDecoder().decode([UInt8].self, from: encoded) == blob)
        let text = String(repeating: "é", count: 300)
        #expect(try CBORDecoder().decode(String.self, from: encode(text)) == text)
    }

    @Test("Optional values at the top level")
    func topLevelOptional() throws {
        #expect(try encode(Int?.none) == hex("f6"))
        #expect(try encode(Int?.some(3)) == hex("03"))
        #expect(try decode(Int?.self, "f6") == nil)
        #expect(try decode(Int?.self, "03") == 3)
    }

    // MARK: userInfo

    static let userInfoKey = CodingUserInfoKey(rawValue: "test.cbor")!

    struct ReadsUserInfo: Codable, Equatable {
        let value: String

        init(value: String) { self.value = value }

        init(from decoder: any Decoder) throws {
            value = decoder.userInfo[CBORCoderTests.userInfoKey] as? String ?? "missing"
        }

        func encode(to encoder: any Encoder) throws {
            var container = encoder.singleValueContainer()
            try container.encode(encoder.userInfo[CBORCoderTests.userInfoKey] as? String ?? "missing")
        }
    }

    @Test("userInfo reaches the encoded and decoded types, including nested ones")
    func userInfo() throws {
        var encoder = CBOREncoder()
        encoder.userInfo[Self.userInfoKey] = "hello"
        #expect(try encoder.encode(ReadsUserInfo(value: "")) == hex("65 68656c6c6f"))
        #expect(try encoder.encode(["k": [ReadsUserInfo(value: "")]]) == hex("a1 616b 81 65 68656c6c6f"))
        #expect(try CBOREncoder().encode(ReadsUserInfo(value: "")) == hex("67 6d697373696e67"))

        var decoder = CBORDecoder()
        decoder.userInfo[Self.userInfoKey] = "hello"
        #expect(try decoder.decode(ReadsUserInfo.self, from: hex("00")).value == "hello")
        #expect(try decoder.decode([String: [ReadsUserInfo]].self, from: hex("a1 616b 81 00"))["k"]?.first?.value == "hello")
        #expect(try CBORDecoder().decode(ReadsUserInfo.self, from: hex("00")).value == "missing")
    }

    // MARK: Hand written containers

    @Test("Nested containers written by hand round trip")
    func nestedContainers() throws {
        struct Manual: Codable, Equatable {
            var a = 1
            var b = [1, 2]
            enum Keys: String, CodingKey { case outer, list }
            enum Inner: String, CodingKey { case a }

            init() {}

            func encode(to encoder: any Encoder) throws {
                var container = encoder.container(keyedBy: Keys.self)
                var outer = container.nestedContainer(keyedBy: Inner.self, forKey: .outer)
                try outer.encode(a, forKey: .a)
                var list = container.nestedUnkeyedContainer(forKey: .list)
                for value in b { try list.encode(value) }
            }

            init(from decoder: any Decoder) throws {
                let container = try decoder.container(keyedBy: Keys.self)
                let outer = try container.nestedContainer(keyedBy: Inner.self, forKey: .outer)
                a = try outer.decode(Int.self, forKey: .a)
                var list = try container.nestedUnkeyedContainer(forKey: .list)
                var values: [Int] = []
                while !list.isAtEnd { values.append(try list.decode(Int.self)) }
                b = values
            }
        }
        let bytes = try encode(Manual())
        #expect(bytes == hex("a2 656f75746572 a1 6161 01 646c697374 82 0102"))
        #expect(try CBORDecoder().decode(Manual.self, from: bytes) == Manual())
    }
}
