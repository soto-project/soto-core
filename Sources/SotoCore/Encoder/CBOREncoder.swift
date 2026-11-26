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

/// Encodes `Encodable` values as CBOR (RFC 8949).
///
/// - Integers use the smallest encoding that holds the value.
/// - `Double` is written as a 64 bit float and `Float` as a 32 bit float.
/// - `Date` is written as tag 1, as an integer when it is a whole number of seconds and as a float otherwise.
/// - `Data` and `[UInt8]` are written as byte strings.
/// - Optionals that are `nil` are left out of keyed containers.
public struct CBOREncoder {
    /// Contextual user-provided information for use during encoding.
    public var userInfo: [CodingUserInfoKey: Any] = [:]

    public init() {}

    /// Encode a value as CBOR.
    public func encode<T: Encodable>(_ value: T) throws -> [UInt8] {
        let node = try CBOREncoderImpl.makeNode(value, codingPath: [], userInfo: self.userInfo)
        var output: [UInt8] = []
        node.serialize(into: &output)
        return output
    }

    /// Encode a value as CBOR into a `ByteBuffer`.
    public func encodeAsByteBuffer<T: Encodable>(_ value: T, allocator: ByteBufferAllocator) throws -> ByteBuffer {
        let bytes = try self.encode(value)
        var buffer = allocator.buffer(capacity: bytes.count)
        buffer.writeBytes(bytes)
        return buffer
    }
}

// MARK: - Output tree

/// Mutable tree the encoder containers write into. It is turned into bytes once encoding has finished.
final class CBOREncodingNode {
    enum Storage {
        case unset
        case leaf(CBORValue)
        case array([CBOREncodingNode])
        case map([(key: String, node: CBOREncodingNode)])
    }

    var storage: Storage = .unset

    init() {}

    init(_ value: CBORValue) {
        self.storage = .leaf(value)
    }

    func appendToArray(_ node: CBOREncodingNode) {
        if case .array(var nodes) = storage {
            storage = .unset
            nodes.append(node)
            storage = .array(nodes)
        } else {
            storage = .array([node])
        }
    }

    func appendToMap(key: String, _ node: CBOREncodingNode) {
        if case .map(var entries) = storage {
            storage = .unset
            entries.append((key, node))
            storage = .map(entries)
        } else {
            storage = .map([(key, node)])
        }
    }

    func serialize(into output: inout [UInt8]) {
        switch storage {
        case .unset:
            // a container that was requested but never written to is an empty map
            Self.writeHead(CBORMajorType.map, 0, into: &output)
        case .leaf(let value):
            Self.serialize(value, into: &output)
        case .array(let nodes):
            Self.writeHead(CBORMajorType.array, UInt64(nodes.count), into: &output)
            for node in nodes {
                node.serialize(into: &output)
            }
        case .map(let entries):
            Self.writeHead(CBORMajorType.map, UInt64(entries.count), into: &output)
            for entry in entries {
                let utf8 = entry.key.utf8
                Self.writeHead(CBORMajorType.text, UInt64(utf8.count), into: &output)
                output.append(contentsOf: utf8)
                entry.node.serialize(into: &output)
            }
        }
    }

    /// Write the initial byte and argument using the shortest form.
    static func writeHead(_ major: UInt8, _ argument: UInt64, into output: inout [UInt8]) {
        let major = major << 5
        switch argument {
        case 0..<24:
            output.append(major | UInt8(argument))
        case 24...UInt64(UInt8.max):
            output.append(major | 24)
            output.append(UInt8(argument))
        case UInt64(UInt8.max) + 1...UInt64(UInt16.max):
            output.append(major | 25)
            withUnsafeBytes(of: UInt16(argument).bigEndian) { output.append(contentsOf: $0) }
        case UInt64(UInt16.max) + 1...UInt64(UInt32.max):
            output.append(major | 26)
            withUnsafeBytes(of: UInt32(argument).bigEndian) { output.append(contentsOf: $0) }
        default:
            output.append(major | 27)
            withUnsafeBytes(of: argument.bigEndian) { output.append(contentsOf: $0) }
        }
    }

    private static func serialize(_ value: CBORValue, into output: inout [UInt8]) {
        switch value {
        case .unsigned(let value):
            writeHead(CBORMajorType.unsigned, value, into: &output)
        case .negative(let value):
            writeHead(CBORMajorType.negative, value, into: &output)
        case .bytes(let bytes):
            writeHead(CBORMajorType.bytes, UInt64(bytes.count), into: &output)
            output.append(contentsOf: bytes)
        case .text(let string):
            let utf8 = string.utf8
            writeHead(CBORMajorType.text, UInt64(utf8.count), into: &output)
            output.append(contentsOf: utf8)
        case .bool(let value):
            output.append(value ? 0xf5 : 0xf4)
        case .null:
            output.append(0xf6)
        case .double(let value):
            output.append(0xfb)
            withUnsafeBytes(of: value.bitPattern.bigEndian) { output.append(contentsOf: $0) }
        case .float(let value):
            output.append(0xfa)
            withUnsafeBytes(of: value.bitPattern.bigEndian) { output.append(contentsOf: $0) }
        case .date(let seconds):
            writeHead(CBORMajorType.tag, 1, into: &output)
            // 2^53 is the largest magnitude where every whole number is exactly representable
            if seconds == seconds.rounded(), abs(seconds) < 9_007_199_254_740_992, let integer = Int64(exactly: seconds) {
                if integer >= 0 {
                    writeHead(CBORMajorType.unsigned, UInt64(integer), into: &output)
                } else {
                    writeHead(CBORMajorType.negative, UInt64(-1 - integer), into: &output)
                }
            } else {
                serialize(.double(seconds), into: &output)
            }
        case .array, .map:
            preconditionFailure("Nested containers are written through CBOREncodingNode")
        }
    }
}

// MARK: - Encoder

final class CBOREncoderImpl: Encoder {
    let node: CBOREncodingNode
    let codingPath: [any CodingKey]
    let userInfo: [CodingUserInfoKey: Any]

    init(node: CBOREncodingNode, codingPath: [any CodingKey], userInfo: [CodingUserInfoKey: Any]) {
        self.node = node
        self.codingPath = codingPath
        self.userInfo = userInfo
    }

    /// Encode a value into a new node. `Date`, `Data` and `[UInt8]` have a native CBOR representation
    /// and are written directly instead of through their `Encodable` implementations.
    static func makeNode<T: Encodable>(_ value: T, codingPath: [any CodingKey], userInfo: [CodingUserInfoKey: Any]) throws -> CBOREncodingNode {
        if let date = value as? Date {
            return CBOREncodingNode(.date(date.timeIntervalSince1970))
        }
        if let data = value as? Data {
            return CBOREncodingNode(.bytes([UInt8](data)))
        }
        // Compare the static type: a dynamic cast would also accept an empty array of any other element type
        if T.self == [UInt8].self {
            return CBOREncodingNode(.bytes(value as! [UInt8]))
        }
        let encoder = CBOREncoderImpl(node: CBOREncodingNode(), codingPath: codingPath, userInfo: userInfo)
        try value.encode(to: encoder)
        return encoder.node
    }

    func container<Key: CodingKey>(keyedBy type: Key.Type) -> KeyedEncodingContainer<Key> {
        self.node.storage = .map([])
        return KeyedEncodingContainer(KeyedContainer<Key>(node: node, codingPath: codingPath, userInfo: userInfo))
    }

    func unkeyedContainer() -> any UnkeyedEncodingContainer {
        self.node.storage = .array([])
        return UnkeyedContainer(node: node, codingPath: codingPath, userInfo: userInfo)
    }

    func singleValueContainer() -> any SingleValueEncodingContainer {
        SingleValueContainer(node: node, codingPath: codingPath, userInfo: userInfo)
    }

    // MARK: Keyed

    struct KeyedContainer<Key: CodingKey>: KeyedEncodingContainerProtocol {
        let node: CBOREncodingNode
        let codingPath: [any CodingKey]
        let userInfo: [CodingUserInfoKey: Any]

        private func set(_ value: CBORValue, forKey key: Key) {
            node.appendToMap(key: key.stringValue, CBOREncodingNode(value))
        }

        mutating func encodeNil(forKey key: Key) throws { set(.null, forKey: key) }
        mutating func encode(_ value: Bool, forKey key: Key) throws { set(.bool(value), forKey: key) }
        mutating func encode(_ value: String, forKey key: Key) throws { set(.text(value), forKey: key) }
        mutating func encode(_ value: Double, forKey key: Key) throws { set(.double(value), forKey: key) }
        mutating func encode(_ value: Float, forKey key: Key) throws { set(.float(value), forKey: key) }
        mutating func encode(_ value: Int, forKey key: Key) throws { set(CBOREncoderImpl.integer(value), forKey: key) }
        mutating func encode(_ value: Int8, forKey key: Key) throws { set(CBOREncoderImpl.integer(value), forKey: key) }
        mutating func encode(_ value: Int16, forKey key: Key) throws { set(CBOREncoderImpl.integer(value), forKey: key) }
        mutating func encode(_ value: Int32, forKey key: Key) throws { set(CBOREncoderImpl.integer(value), forKey: key) }
        mutating func encode(_ value: Int64, forKey key: Key) throws { set(CBOREncoderImpl.integer(value), forKey: key) }
        mutating func encode(_ value: UInt, forKey key: Key) throws { set(CBOREncoderImpl.integer(value), forKey: key) }
        mutating func encode(_ value: UInt8, forKey key: Key) throws { set(CBOREncoderImpl.integer(value), forKey: key) }
        mutating func encode(_ value: UInt16, forKey key: Key) throws { set(CBOREncoderImpl.integer(value), forKey: key) }
        mutating func encode(_ value: UInt32, forKey key: Key) throws { set(CBOREncoderImpl.integer(value), forKey: key) }
        mutating func encode(_ value: UInt64, forKey key: Key) throws { set(CBOREncoderImpl.integer(value), forKey: key) }

        mutating func encode<T: Encodable>(_ value: T, forKey key: Key) throws {
            let child = try CBOREncoderImpl.makeNode(value, codingPath: codingPath + [key], userInfo: userInfo)
            node.appendToMap(key: key.stringValue, child)
        }

        mutating func nestedContainer<NestedKey: CodingKey>(keyedBy keyType: NestedKey.Type, forKey key: Key) -> KeyedEncodingContainer<NestedKey> {
            let child = CBOREncodingNode()
            child.storage = .map([])
            node.appendToMap(key: key.stringValue, child)
            return KeyedEncodingContainer(
                KeyedContainer<NestedKey>(node: child, codingPath: codingPath + [key], userInfo: userInfo)
            )
        }

        mutating func nestedUnkeyedContainer(forKey key: Key) -> any UnkeyedEncodingContainer {
            let child = CBOREncodingNode()
            child.storage = .array([])
            node.appendToMap(key: key.stringValue, child)
            return UnkeyedContainer(node: child, codingPath: codingPath + [key], userInfo: userInfo)
        }

        mutating func superEncoder() -> any Encoder {
            superEncoder(forKey: "super")
        }

        mutating func superEncoder(forKey key: Key) -> any Encoder {
            superEncoder(forKey: key.stringValue)
        }

        private func superEncoder(forKey key: String) -> any Encoder {
            let child = CBOREncodingNode()
            node.appendToMap(key: key, child)
            return CBOREncoderImpl(node: child, codingPath: codingPath, userInfo: userInfo)
        }
    }

    // MARK: Unkeyed

    struct UnkeyedContainer: UnkeyedEncodingContainer {
        let node: CBOREncodingNode
        let codingPath: [any CodingKey]
        let userInfo: [CodingUserInfoKey: Any]

        var count: Int {
            if case .array(let nodes) = node.storage { return nodes.count }
            return 0
        }

        private var nextKey: IndexKey { IndexKey(intValue: count) }

        private func append(_ value: CBORValue) {
            node.appendToArray(CBOREncodingNode(value))
        }

        mutating func encodeNil() throws { append(.null) }
        mutating func encode(_ value: Bool) throws { append(.bool(value)) }
        mutating func encode(_ value: String) throws { append(.text(value)) }
        mutating func encode(_ value: Double) throws { append(.double(value)) }
        mutating func encode(_ value: Float) throws { append(.float(value)) }
        mutating func encode(_ value: Int) throws { append(CBOREncoderImpl.integer(value)) }
        mutating func encode(_ value: Int8) throws { append(CBOREncoderImpl.integer(value)) }
        mutating func encode(_ value: Int16) throws { append(CBOREncoderImpl.integer(value)) }
        mutating func encode(_ value: Int32) throws { append(CBOREncoderImpl.integer(value)) }
        mutating func encode(_ value: Int64) throws { append(CBOREncoderImpl.integer(value)) }
        mutating func encode(_ value: UInt) throws { append(CBOREncoderImpl.integer(value)) }
        mutating func encode(_ value: UInt8) throws { append(CBOREncoderImpl.integer(value)) }
        mutating func encode(_ value: UInt16) throws { append(CBOREncoderImpl.integer(value)) }
        mutating func encode(_ value: UInt32) throws { append(CBOREncoderImpl.integer(value)) }
        mutating func encode(_ value: UInt64) throws { append(CBOREncoderImpl.integer(value)) }

        mutating func encode<T: Encodable>(_ value: T) throws {
            let child = try CBOREncoderImpl.makeNode(value, codingPath: codingPath + [nextKey], userInfo: userInfo)
            node.appendToArray(child)
        }

        mutating func nestedContainer<NestedKey: CodingKey>(keyedBy keyType: NestedKey.Type) -> KeyedEncodingContainer<NestedKey> {
            let key = nextKey
            let child = CBOREncodingNode()
            child.storage = .map([])
            node.appendToArray(child)
            return KeyedEncodingContainer(
                KeyedContainer<NestedKey>(node: child, codingPath: codingPath + [key], userInfo: userInfo)
            )
        }

        mutating func nestedUnkeyedContainer() -> any UnkeyedEncodingContainer {
            let key = nextKey
            let child = CBOREncodingNode()
            child.storage = .array([])
            node.appendToArray(child)
            return UnkeyedContainer(node: child, codingPath: codingPath + [key], userInfo: userInfo)
        }

        mutating func superEncoder() -> any Encoder {
            let key = nextKey
            let child = CBOREncodingNode()
            node.appendToArray(child)
            return CBOREncoderImpl(node: child, codingPath: codingPath + [key], userInfo: userInfo)
        }
    }

    // MARK: Single value

    struct SingleValueContainer: SingleValueEncodingContainer {
        let node: CBOREncodingNode
        let codingPath: [any CodingKey]
        let userInfo: [CodingUserInfoKey: Any]

        private func set(_ value: CBORValue) {
            node.storage = .leaf(value)
        }

        mutating func encodeNil() throws { set(.null) }
        mutating func encode(_ value: Bool) throws { set(.bool(value)) }
        mutating func encode(_ value: String) throws { set(.text(value)) }
        mutating func encode(_ value: Double) throws { set(.double(value)) }
        mutating func encode(_ value: Float) throws { set(.float(value)) }
        mutating func encode(_ value: Int) throws { set(CBOREncoderImpl.integer(value)) }
        mutating func encode(_ value: Int8) throws { set(CBOREncoderImpl.integer(value)) }
        mutating func encode(_ value: Int16) throws { set(CBOREncoderImpl.integer(value)) }
        mutating func encode(_ value: Int32) throws { set(CBOREncoderImpl.integer(value)) }
        mutating func encode(_ value: Int64) throws { set(CBOREncoderImpl.integer(value)) }
        mutating func encode(_ value: UInt) throws { set(CBOREncoderImpl.integer(value)) }
        mutating func encode(_ value: UInt8) throws { set(CBOREncoderImpl.integer(value)) }
        mutating func encode(_ value: UInt16) throws { set(CBOREncoderImpl.integer(value)) }
        mutating func encode(_ value: UInt32) throws { set(CBOREncoderImpl.integer(value)) }
        mutating func encode(_ value: UInt64) throws { set(CBOREncoderImpl.integer(value)) }

        mutating func encode<T: Encodable>(_ value: T) throws {
            let child = try CBOREncoderImpl.makeNode(value, codingPath: codingPath, userInfo: userInfo)
            node.storage = child.storage
        }
    }

    // MARK: Helpers

    static func integer<I: BinaryInteger>(_ value: I) -> CBORValue {
        if value < 0 {
            // -1 - value, computed on the magnitude so it cannot overflow
            return .negative(UInt64(truncatingIfNeeded: ~value))
        }
        return .unsigned(UInt64(truncatingIfNeeded: value))
    }

    struct IndexKey: CodingKey {
        var stringValue: String { "Index \(intValue!)" }
        var intValue: Int?

        init(intValue: Int) {
            self.intValue = intValue
        }

        init?(stringValue: String) { nil }
    }
}
