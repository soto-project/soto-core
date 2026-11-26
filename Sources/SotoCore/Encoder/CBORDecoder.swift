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

public import NIOCore

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif

/// Decodes `Decodable` values from CBOR (RFC 8949).
///
/// - Definite and indefinite length strings, arrays and maps are supported.
/// - Tag 1 is decoded as a `Date` from an integer or float. All other tags are skipped and their content is used.
/// - Half, single and double precision floats are decoded.
/// - Byte strings decode to `Data` and `[UInt8]`.
/// - Malformed or truncated input, trailing bytes, and nesting deeper than 128 levels throw ``CBORError``.
public struct CBORDecoder {
    /// Maximum nesting of arrays, maps and tags
    static let maxNestingDepth = 128

    /// Contextual user-provided information for use during decoding.
    public var userInfo: [CodingUserInfoKey: Any] = [:]

    public init() {}

    /// Decode a value from CBOR held in a `ByteBuffer`.
    public func decode<T: Decodable>(_ type: T.Type, from buffer: ByteBuffer) throws -> T {
        try self.decode(type, from: Array(buffer.readableBytesView))
    }

    /// Decode a value from CBOR held in a byte array.
    public func decode<T: Decodable>(_ type: T.Type, from data: [UInt8]) throws -> T {
        var parser = CBORParser(bytes: data, maxDepth: Self.maxNestingDepth)
        let value = try parser.parseTopLevel()
        let decoder = CBORDecoderImpl(value: value, codingPath: [], userInfo: self.userInfo)
        return try CBORDecoderImpl.unbox(value, as: type, codingPath: [], userInfo: self.userInfo, decoder: decoder)
    }
}

// MARK: - Parser

/// Turns CBOR bytes into a ``CBORValue`` tree.
struct CBORParser {
    let bytes: [UInt8]
    let maxDepth: Int
    var position = 0

    init(bytes: [UInt8], maxDepth: Int) {
        self.bytes = bytes
        self.maxDepth = maxDepth
    }

    mutating func parseTopLevel() throws -> CBORValue {
        let value = try self.parse(depth: 0)
        guard self.position == self.bytes.count else { throw CBORError.trailingData }
        return value
    }

    private var remaining: Int { self.bytes.count - self.position }

    private mutating func readByte() throws -> UInt8 {
        guard self.position < self.bytes.count else { throw CBORError.truncatedInput }
        defer { self.position += 1 }
        return self.bytes[self.position]
    }

    private mutating func readBigEndian(_ count: Int) throws -> UInt64 {
        guard count <= self.remaining else { throw CBORError.truncatedInput }
        var result: UInt64 = 0
        for _ in 0..<count {
            result = (result << 8) | UInt64(self.bytes[self.position])
            self.position += 1
        }
        return result
    }

    private mutating func readBytes(_ count: UInt64) throws -> ArraySlice<UInt8> {
        guard count <= UInt64(self.remaining) else { throw CBORError.truncatedInput }
        let end = self.position + Int(count)
        defer { self.position = end }
        return self.bytes[self.position..<end]
    }

    /// Read the argument that follows an initial byte. Indefinite length (31) is handled by the callers.
    private mutating func readArgument(_ info: UInt8) throws -> UInt64 {
        switch info {
        case 0..<24: return UInt64(info)
        case 24: return try self.readBigEndian(1)
        case 25: return try self.readBigEndian(2)
        case 26: return try self.readBigEndian(4)
        case 27: return try self.readBigEndian(8)
        default: throw CBORError.malformed("Reserved additional information value \(info)")
        }
    }

    private mutating func atBreak() throws -> Bool {
        guard self.position < self.bytes.count else { throw CBORError.truncatedInput }
        if self.bytes[self.position] == 0xff {
            self.position += 1
            return true
        }
        return false
    }

    /// Read the chunks of an indefinite length byte or text string
    private mutating func readChunks(major: UInt8) throws -> [UInt8] {
        var result: [UInt8] = []
        while try !self.atBreak() {
            let initial = try self.readByte()
            guard initial >> 5 == major, initial & 0x1f != 31 else {
                throw CBORError.malformed("Invalid chunk in indefinite length string")
            }
            let length = try self.readArgument(initial & 0x1f)
            result.append(contentsOf: try self.readBytes(length))
        }
        return result
    }

    private func makeString(_ bytes: some Collection<UInt8>) throws -> String {
        guard let string = String(validating: bytes, as: UTF8.self) else {
            throw CBORError.malformed("Text string is not valid UTF-8")
        }
        return string
    }

    mutating func parse(depth: Int) throws -> CBORValue {
        guard depth <= self.maxDepth else { throw CBORError.nestingTooDeep }
        let initial = try self.readByte()
        let major = initial >> 5
        let info = initial & 0x1f

        switch major {
        case CBORMajorType.unsigned:
            return .unsigned(try self.readArgument(info))

        case CBORMajorType.negative:
            return .negative(try self.readArgument(info))

        case CBORMajorType.bytes:
            if info == 31 {
                return .bytes(try self.readChunks(major: major))
            }
            return .bytes(Array(try self.readBytes(try self.readArgument(info))))

        case CBORMajorType.text:
            if info == 31 {
                return .text(try self.makeString(try self.readChunks(major: major)))
            }
            return .text(try self.makeString(try self.readBytes(try self.readArgument(info))))

        case CBORMajorType.array:
            var items: [CBORValue] = []
            if info == 31 {
                while try !self.atBreak() {
                    items.append(try self.parse(depth: depth + 1))
                }
            } else {
                let count = try self.readArgument(info)
                // every item takes at least one byte, so this stops huge counts allocating memory
                guard count <= UInt64(self.remaining) else { throw CBORError.truncatedInput }
                items.reserveCapacity(Int(count))
                for _ in 0..<count {
                    items.append(try self.parse(depth: depth + 1))
                }
            }
            return .array(items)

        case CBORMajorType.map:
            var entries: [(key: CBORValue, value: CBORValue)] = []
            if info == 31 {
                while try !self.atBreak() {
                    let key = try self.parse(depth: depth + 1)
                    entries.append((key, try self.parse(depth: depth + 1)))
                }
            } else {
                let count = try self.readArgument(info)
                // every entry takes at least two bytes
                guard count <= UInt64(self.remaining) else { throw CBORError.truncatedInput }
                entries.reserveCapacity(Int(count))
                for _ in 0..<count {
                    let key = try self.parse(depth: depth + 1)
                    entries.append((key, try self.parse(depth: depth + 1)))
                }
            }
            return .map(entries)

        case CBORMajorType.tag:
            let tag = try self.readArgument(info)
            let content = try self.parse(depth: depth + 1)
            guard tag == 1 else { return content }
            switch content {
            case .unsigned(let value): return .date(Double(value))
            case .negative(let value): return .date(-1 - Double(value))
            case .double(let value): return .date(value)
            default: throw CBORError.malformed("Tag 1 must contain an integer or a float")
            }

        default:
            switch info {
            case 20: return .bool(false)
            case 21: return .bool(true)
            case 22, 23: return .null  // null and undefined
            case 25: return .double(Self.halfToDouble(UInt16(try self.readBigEndian(2))))
            case 26: return .double(Double(Float(bitPattern: UInt32(try self.readBigEndian(4)))))
            case 27: return .double(Double(bitPattern: try self.readBigEndian(8)))
            case 31: throw CBORError.malformed("Unexpected break")
            default: throw CBORError.malformed("Unsupported simple value \(info)")
            }
        }
    }

    /// IEEE 754 half precision to double
    static func halfToDouble(_ half: UInt16) -> Double {
        let sign = half & 0x8000 != 0 ? -1.0 : 1.0
        let exponent = Int((half >> 10) & 0x1f)
        let mantissa = Double(half & 0x3ff)
        switch exponent {
        case 0: return sign * mantissa * 0x1p-24
        case 31: return mantissa == 0 ? sign * .infinity : .nan
        default: return sign * (1 + mantissa * 0x1p-10) * Double(sign: .plus, exponent: exponent - 15, significand: 1)
        }
    }
}

// MARK: - Decoder

final class CBORDecoderImpl: Decoder {
    let value: CBORValue
    let codingPath: [any CodingKey]
    let userInfo: [CodingUserInfoKey: Any]

    init(value: CBORValue, codingPath: [any CodingKey], userInfo: [CodingUserInfoKey: Any]) {
        self.value = value
        self.codingPath = codingPath
        self.userInfo = userInfo
    }

    func container<Key: CodingKey>(keyedBy type: Key.Type) throws -> KeyedDecodingContainer<Key> {
        guard case .map(let entries) = value else {
            throw Self.mismatch([String: Any].self, value, codingPath: codingPath)
        }
        var map: [String: CBORValue] = [:]
        for entry in entries {
            switch entry.key {
            case .text(let key): map[key] = entry.value
            case .unsigned(let key): map[String(key)] = entry.value
            case .negative(let key):
                // The key is -1 - n. For n == UInt64.max the magnitude is 2^64, which does not fit in a UInt64.
                guard key < UInt64.max else {
                    throw DecodingError.dataCorrupted(.init(codingPath: codingPath, debugDescription: "Negative integer map key is out of range"))
                }
                map["-\(key + 1)"] = entry.value
            default:
                throw DecodingError.dataCorrupted(.init(codingPath: codingPath, debugDescription: "Map keys must be strings or integers"))
            }
        }
        return KeyedDecodingContainer(KeyedContainer<Key>(map: map, codingPath: codingPath, userInfo: userInfo))
    }

    func unkeyedContainer() throws -> any UnkeyedDecodingContainer {
        guard case .array(let items) = value else {
            throw Self.mismatch([Any].self, value, codingPath: codingPath)
        }
        return UnkeyedContainer(items: items, codingPath: codingPath, userInfo: userInfo)
    }

    func singleValueContainer() throws -> any SingleValueDecodingContainer {
        SingleValueContainer(value: value, codingPath: codingPath, userInfo: userInfo)
    }

    // MARK: Keyed

    struct KeyedContainer<Key: CodingKey>: KeyedDecodingContainerProtocol {
        let map: [String: CBORValue]
        let codingPath: [any CodingKey]
        let userInfo: [CodingUserInfoKey: Any]

        var allKeys: [Key] { map.keys.compactMap { Key(stringValue: $0) } }

        func contains(_ key: Key) -> Bool { map[key.stringValue] != nil }

        private func entry(_ key: Key) throws -> CBORValue {
            guard let value = map[key.stringValue] else {
                throw DecodingError.keyNotFound(
                    key,
                    .init(codingPath: codingPath, debugDescription: "No value associated with key \(key.stringValue)")
                )
            }
            return value
        }

        func decodeNil(forKey key: Key) throws -> Bool {
            if case .null = try entry(key) { return true }
            return false
        }

        func decode(_ type: Bool.Type, forKey key: Key) throws -> Bool { try CBORDecoderImpl.unboxBool(entry(key), codingPath + [key]) }
        func decode(_ type: String.Type, forKey key: Key) throws -> String { try CBORDecoderImpl.unboxString(entry(key), codingPath + [key]) }
        func decode(_ type: Double.Type, forKey key: Key) throws -> Double { try CBORDecoderImpl.unboxDouble(entry(key), codingPath + [key]) }
        func decode(_ type: Float.Type, forKey key: Key) throws -> Float { Float(try CBORDecoderImpl.unboxDouble(entry(key), codingPath + [key])) }
        func decode(_ type: Int.Type, forKey key: Key) throws -> Int { try CBORDecoderImpl.unboxInteger(entry(key), codingPath + [key]) }
        func decode(_ type: Int8.Type, forKey key: Key) throws -> Int8 { try CBORDecoderImpl.unboxInteger(entry(key), codingPath + [key]) }
        func decode(_ type: Int16.Type, forKey key: Key) throws -> Int16 { try CBORDecoderImpl.unboxInteger(entry(key), codingPath + [key]) }
        func decode(_ type: Int32.Type, forKey key: Key) throws -> Int32 { try CBORDecoderImpl.unboxInteger(entry(key), codingPath + [key]) }
        func decode(_ type: Int64.Type, forKey key: Key) throws -> Int64 { try CBORDecoderImpl.unboxInteger(entry(key), codingPath + [key]) }
        func decode(_ type: UInt.Type, forKey key: Key) throws -> UInt { try CBORDecoderImpl.unboxInteger(entry(key), codingPath + [key]) }
        func decode(_ type: UInt8.Type, forKey key: Key) throws -> UInt8 { try CBORDecoderImpl.unboxInteger(entry(key), codingPath + [key]) }
        func decode(_ type: UInt16.Type, forKey key: Key) throws -> UInt16 { try CBORDecoderImpl.unboxInteger(entry(key), codingPath + [key]) }
        func decode(_ type: UInt32.Type, forKey key: Key) throws -> UInt32 { try CBORDecoderImpl.unboxInteger(entry(key), codingPath + [key]) }
        func decode(_ type: UInt64.Type, forKey key: Key) throws -> UInt64 { try CBORDecoderImpl.unboxInteger(entry(key), codingPath + [key]) }

        func decode<T: Decodable>(_ type: T.Type, forKey key: Key) throws -> T {
            let path = codingPath + [key]
            return try CBORDecoderImpl.unbox(try entry(key), as: type, codingPath: path, userInfo: userInfo)
        }

        func nestedContainer<NestedKey: CodingKey>(keyedBy type: NestedKey.Type, forKey key: Key) throws -> KeyedDecodingContainer<NestedKey> {
            try decoder(forKey: key).container(keyedBy: type)
        }

        func nestedUnkeyedContainer(forKey key: Key) throws -> any UnkeyedDecodingContainer {
            try decoder(forKey: key).unkeyedContainer()
        }

        func superDecoder() throws -> any Decoder {
            CBORDecoderImpl(value: map["super"] ?? .null, codingPath: codingPath, userInfo: userInfo)
        }

        func superDecoder(forKey key: Key) throws -> any Decoder {
            try decoder(forKey: key)
        }

        private func decoder(forKey key: Key) throws -> CBORDecoderImpl {
            CBORDecoderImpl(value: try entry(key), codingPath: codingPath + [key], userInfo: userInfo)
        }
    }

    // MARK: Unkeyed

    struct UnkeyedContainer: UnkeyedDecodingContainer {
        let items: [CBORValue]
        let codingPath: [any CodingKey]
        let userInfo: [CodingUserInfoKey: Any]
        private(set) var currentIndex = 0

        init(items: [CBORValue], codingPath: [any CodingKey], userInfo: [CodingUserInfoKey: Any]) {
            self.items = items
            self.codingPath = codingPath
            self.userInfo = userInfo
        }

        var count: Int? { items.count }
        var isAtEnd: Bool { currentIndex >= items.count }

        private var currentPath: [any CodingKey] { codingPath + [CBOREncoderImpl.IndexKey(intValue: currentIndex)] }

        /// Return the next item and move past it
        private mutating func next<T>(_ type: T.Type) throws -> CBORValue {
            guard !isAtEnd else {
                throw DecodingError.valueNotFound(type, .init(codingPath: currentPath, debugDescription: "Unkeyed container is at end"))
            }
            defer { currentIndex += 1 }
            return items[currentIndex]
        }

        mutating func decodeNil() throws -> Bool {
            guard !isAtEnd else {
                throw DecodingError.valueNotFound(Any?.self, .init(codingPath: currentPath, debugDescription: "Unkeyed container is at end"))
            }
            if case .null = items[currentIndex] {
                currentIndex += 1
                return true
            }
            return false
        }

        mutating func decode(_ type: Bool.Type) throws -> Bool {
            let p = currentPath
            return try CBORDecoderImpl.unboxBool(next(type), p)
        }
        mutating func decode(_ type: String.Type) throws -> String {
            let p = currentPath
            return try CBORDecoderImpl.unboxString(next(type), p)
        }
        mutating func decode(_ type: Double.Type) throws -> Double {
            let p = currentPath
            return try CBORDecoderImpl.unboxDouble(next(type), p)
        }
        mutating func decode(_ type: Float.Type) throws -> Float {
            let p = currentPath
            return Float(try CBORDecoderImpl.unboxDouble(next(type), p))
        }
        mutating func decode(_ type: Int.Type) throws -> Int {
            let p = currentPath
            return try CBORDecoderImpl.unboxInteger(next(type), p)
        }
        mutating func decode(_ type: Int8.Type) throws -> Int8 {
            let p = currentPath
            return try CBORDecoderImpl.unboxInteger(next(type), p)
        }
        mutating func decode(_ type: Int16.Type) throws -> Int16 {
            let p = currentPath
            return try CBORDecoderImpl.unboxInteger(next(type), p)
        }
        mutating func decode(_ type: Int32.Type) throws -> Int32 {
            let p = currentPath
            return try CBORDecoderImpl.unboxInteger(next(type), p)
        }
        mutating func decode(_ type: Int64.Type) throws -> Int64 {
            let p = currentPath
            return try CBORDecoderImpl.unboxInteger(next(type), p)
        }
        mutating func decode(_ type: UInt.Type) throws -> UInt {
            let p = currentPath
            return try CBORDecoderImpl.unboxInteger(next(type), p)
        }
        mutating func decode(_ type: UInt8.Type) throws -> UInt8 {
            let p = currentPath
            return try CBORDecoderImpl.unboxInteger(next(type), p)
        }
        mutating func decode(_ type: UInt16.Type) throws -> UInt16 {
            let p = currentPath
            return try CBORDecoderImpl.unboxInteger(next(type), p)
        }
        mutating func decode(_ type: UInt32.Type) throws -> UInt32 {
            let p = currentPath
            return try CBORDecoderImpl.unboxInteger(next(type), p)
        }
        mutating func decode(_ type: UInt64.Type) throws -> UInt64 {
            let p = currentPath
            return try CBORDecoderImpl.unboxInteger(next(type), p)
        }

        mutating func decode<T: Decodable>(_ type: T.Type) throws -> T {
            let path = currentPath
            return try CBORDecoderImpl.unbox(try next(type), as: type, codingPath: path, userInfo: userInfo)
        }

        mutating func nestedContainer<NestedKey: CodingKey>(keyedBy type: NestedKey.Type) throws -> KeyedDecodingContainer<NestedKey> {
            let path = currentPath
            return try CBORDecoderImpl(value: next(type), codingPath: path, userInfo: userInfo).container(keyedBy: type)
        }

        mutating func nestedUnkeyedContainer() throws -> any UnkeyedDecodingContainer {
            let path = currentPath
            return try CBORDecoderImpl(value: next([Any].self), codingPath: path, userInfo: userInfo).unkeyedContainer()
        }

        mutating func superDecoder() throws -> any Decoder {
            let path = currentPath
            return CBORDecoderImpl(value: try next((any Decoder).self), codingPath: path, userInfo: userInfo)
        }
    }

    // MARK: Single value

    struct SingleValueContainer: SingleValueDecodingContainer {
        let value: CBORValue
        let codingPath: [any CodingKey]
        let userInfo: [CodingUserInfoKey: Any]

        func decodeNil() -> Bool {
            if case .null = value { return true }
            return false
        }

        func decode(_ type: Bool.Type) throws -> Bool { try CBORDecoderImpl.unboxBool(value, codingPath) }
        func decode(_ type: String.Type) throws -> String { try CBORDecoderImpl.unboxString(value, codingPath) }
        func decode(_ type: Double.Type) throws -> Double { try CBORDecoderImpl.unboxDouble(value, codingPath) }
        func decode(_ type: Float.Type) throws -> Float { Float(try CBORDecoderImpl.unboxDouble(value, codingPath)) }
        func decode(_ type: Int.Type) throws -> Int { try CBORDecoderImpl.unboxInteger(value, codingPath) }
        func decode(_ type: Int8.Type) throws -> Int8 { try CBORDecoderImpl.unboxInteger(value, codingPath) }
        func decode(_ type: Int16.Type) throws -> Int16 { try CBORDecoderImpl.unboxInteger(value, codingPath) }
        func decode(_ type: Int32.Type) throws -> Int32 { try CBORDecoderImpl.unboxInteger(value, codingPath) }
        func decode(_ type: Int64.Type) throws -> Int64 { try CBORDecoderImpl.unboxInteger(value, codingPath) }
        func decode(_ type: UInt.Type) throws -> UInt { try CBORDecoderImpl.unboxInteger(value, codingPath) }
        func decode(_ type: UInt8.Type) throws -> UInt8 { try CBORDecoderImpl.unboxInteger(value, codingPath) }
        func decode(_ type: UInt16.Type) throws -> UInt16 { try CBORDecoderImpl.unboxInteger(value, codingPath) }
        func decode(_ type: UInt32.Type) throws -> UInt32 { try CBORDecoderImpl.unboxInteger(value, codingPath) }
        func decode(_ type: UInt64.Type) throws -> UInt64 { try CBORDecoderImpl.unboxInteger(value, codingPath) }

        func decode<T: Decodable>(_ type: T.Type) throws -> T {
            try CBORDecoderImpl.unbox(value, as: type, codingPath: codingPath, userInfo: userInfo)
        }
    }

    // MARK: Unboxing

    /// Decode a value. `Date`, `Data` and `[UInt8]` are read from their native CBOR representation
    /// and everything else goes through the type's `Decodable` implementation.
    static func unbox<T: Decodable>(
        _ value: CBORValue,
        as type: T.Type,
        codingPath: [any CodingKey],
        userInfo: [CodingUserInfoKey: Any],
        decoder: CBORDecoderImpl? = nil
    ) throws -> T {
        if type == Date.self {
            let seconds: Double
            switch value {
            case .date(let value), .double(let value): seconds = value
            case .unsigned, .negative: seconds = try unboxDouble(value, codingPath)
            default: throw mismatch(type, value, codingPath: codingPath)
            }
            return Date(timeIntervalSince1970: seconds) as! T
        }
        if type == Data.self, case .bytes(let bytes) = value {
            return Data(bytes) as! T
        }
        if type == [UInt8].self, case .bytes(let bytes) = value {
            return bytes as! T
        }
        let decoder = decoder ?? CBORDecoderImpl(value: value, codingPath: codingPath, userInfo: userInfo)
        return try T(from: decoder)
    }

    static func unboxBool(_ value: CBORValue, _ codingPath: [any CodingKey]) throws -> Bool {
        guard case .bool(let result) = value else { throw mismatch(Bool.self, value, codingPath: codingPath) }
        return result
    }

    static func unboxString(_ value: CBORValue, _ codingPath: [any CodingKey]) throws -> String {
        guard case .text(let result) = value else { throw mismatch(String.self, value, codingPath: codingPath) }
        return result
    }

    static func unboxDouble(_ value: CBORValue, _ codingPath: [any CodingKey]) throws -> Double {
        switch value {
        case .double(let result): return result
        case .unsigned(let result): return Double(result)
        case .negative(let result): return -1 - Double(result)
        default: throw mismatch(Double.self, value, codingPath: codingPath)
        }
    }

    static func unboxInteger<I: FixedWidthInteger>(_ value: CBORValue, _ codingPath: [any CodingKey]) throws -> I {
        let result: I?
        switch value {
        case .unsigned(let number):
            result = I(exactly: number)
        case .negative(let number):
            // the value is -1 - number, which only fits in an Int64 when number <= Int64.max
            result = Int64(exactly: number).flatMap { I(exactly: -1 - $0) }
        default:
            throw mismatch(I.self, value, codingPath: codingPath)
        }
        guard let result else {
            throw DecodingError.dataCorrupted(.init(codingPath: codingPath, debugDescription: "Number does not fit in \(I.self)"))
        }
        return result
    }

    static func mismatch(_ type: Any.Type, _ value: CBORValue, codingPath: [any CodingKey]) -> DecodingError {
        DecodingError.typeMismatch(type, .init(codingPath: codingPath, debugDescription: "Expected \(type) but found \(value.kindDescription)"))
    }
}

extension CBORValue {
    fileprivate var kindDescription: String {
        switch self {
        case .unsigned, .negative: "an integer"
        case .bytes: "a byte string"
        case .text: "a text string"
        case .array: "an array"
        case .map: "a map"
        case .bool: "a bool"
        case .null: "null"
        case .double, .float: "a float"
        case .date: "a date"
        }
    }
}
