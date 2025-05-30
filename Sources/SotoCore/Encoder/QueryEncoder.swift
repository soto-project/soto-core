//===----------------------------------------------------------------------===//
//
// This source file is part of the Soto for AWS open source project
//
// Copyright (c) 2017-2020 the Soto project authors
// Licensed under Apache License v2.0
//
// See LICENSE.txt for license information
// See CONTRIBUTORS.txt for the list of Soto project authors
//
// SPDX-License-Identifier: Apache-2.0
//
//===----------------------------------------------------------------------===//

import struct Foundation.CharacterSet
import struct Foundation.Date
import class Foundation.ISO8601DateFormatter

/// The wrapper struct for encoding Codable classes to Query dictionary
public struct QueryEncoder {
    /// Contextual user-provided information for use during encoding.
    public var userInfo: [CodingUserInfoKey: Any] = [:]

    /// Are we encoding for EC2
    public var ec2: Bool = false

    /// additional keys to include
    public var additionalKeys: [String: String] = [:]

    /// Options set on the top-level encoder to pass down the encoding hierarchy.
    fileprivate struct _Options {
        let userInfo: [CodingUserInfoKey: Any]
        let ec2: Bool
    }

    /// The options set on the top-level encoder.
    fileprivate var options: _Options {
        _Options(userInfo: self.userInfo, ec2: self.ec2)
    }

    public init() {}

    public func encode(_ value: some Encodable) throws -> String? {
        let encoder = _QueryEncoder(options: options)
        try value.encode(to: encoder)

        // encode generates a tree of dictionaries and arrays. We need to flatten this into a single dictionary with keys joined together
        let result = self.flatten(encoder.result)
        return Self.urlEncodeQueryParams(dictionary: result)
    }

    // this list of query allowed characters comes from https://docs.aws.amazon.com/AmazonS3/latest/API/sig-v4-header-based-auth.html
    static let queryAllowedCharacters = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")

    private static func urlEncodeQueryParam(_ value: String) -> String {
        value.addingPercentEncoding(withAllowedCharacters: Self.queryAllowedCharacters) ?? value
    }

    // generate string from
    private static func urlEncodeQueryParams(dictionary: [(key: String, value: String)]) -> String? {
        guard dictionary.count > 0 else { return nil }
        return
            dictionary
            .sorted { $0.key < $1.key }
            .map { "\($0.key)=\(self.urlEncodeQueryParam(String(describing: $0.value)))" }
            .joined(separator: "&")
    }

    /// Flatten dictionary and array tree into one dictionary
    /// - Parameter container: The root container
    private func flatten(_ container: _QueryEncoderKeyedContainer?) -> [(key: String, value: String)] {
        var result: [(key: String, value: String)] = self.additionalKeys.map { return $0 }

        func flatten(dictionary: [String: Any], path: String) {
            for (key, value) in dictionary {
                switch value {
                case let keyed as _QueryEncoderKeyedContainer:
                    flatten(dictionary: keyed.values, path: "\(path)\(key).")
                case let unkeyed as _QueryEncoderUnkeyedContainer:
                    flatten(array: unkeyed.values, path: "\(path)\(key).")
                default:
                    result.append((key: "\(path)\(key)", value: String(describing: value)))
                }
            }
        }
        func flatten(array: [Any], path: String) {
            for iterator in array.enumerated() {
                switch iterator.element {
                case let keyed as _QueryEncoderKeyedContainer:
                    flatten(dictionary: keyed.values, path: "\(path)\(iterator.offset + 1).")
                case let unkeyed as _QueryEncoderUnkeyedContainer:
                    flatten(array: unkeyed.values, path: "\(path)\(iterator.offset + 1)")
                default:
                    result.append((key: "\(path)\(iterator.offset + 1)", value: String(describing: iterator.element)))
                }
            }
        }
        if let container {
            flatten(dictionary: container.values, path: "")
        }
        return result
    }
}

/// class for holding a keyed container (dictionary). Need to encapsulate dictionary in class so we can be sure we are
/// editing the dictionary we push onto the stack
private class _QueryEncoderKeyedContainer {
    private(set) var values: [String: Any] = [:]

    func addChild(path: String, child: Any) {
        self.values[path] = child
    }
}

/// class for holding unkeyed container (array). Need to encapsulate array in class so we can be sure we are
/// editing the array we push onto the stack
private class _QueryEncoderUnkeyedContainer {
    private(set) var values: [Any] = []

    func addChild(_ child: Any) {
        self.values.append(child)
    }
}

/// storage for Query Encoder. Stores a stack of QueryEncoder containers, plus leaf objects
private struct _QueryEncoderStorage {
    /// the container stack
    private var containers: [Any] = []

    /// initializes self with no containers
    init() {}

    /// push a new container onto the storage
    mutating func pushKeyedContainer() -> _QueryEncoderKeyedContainer {
        let container = _QueryEncoderKeyedContainer()
        self.containers.append(container)
        return container
    }

    /// push a new container onto the storage
    mutating func pushUnkeyedContainer() -> _QueryEncoderUnkeyedContainer {
        let container = _QueryEncoderUnkeyedContainer()
        self.containers.append(container)
        return container
    }

    mutating func push(container: Any) {
        self.containers.append(container)
    }

    /// pop a container from the storage
    @discardableResult mutating func popContainer() -> Any {
        self.containers.removeLast()
    }
}

/// Internal QueryEncoder class. Does all the heavy lifting
private class _QueryEncoder: Encoder {
    var codingPath: [CodingKey]

    /// the encoder's storage
    var storage: _QueryEncoderStorage

    /// options
    var options: QueryEncoder._Options

    /// resultant query array
    var result: _QueryEncoderKeyedContainer?

    /// Contextual user-provided information for use during encoding.
    public var userInfo: [CodingUserInfoKey: Any] {
        self.options.userInfo
    }

    /// Initialization
    /// - Parameters:
    ///   - options: options
    ///   - containerCodingMapType: Container encoding for the top level object
    init(options: QueryEncoder._Options) {
        self.storage = _QueryEncoderStorage()
        self.options = options
        self.codingPath = []
        self.result = nil
    }

    func container<Key>(keyedBy type: Key.Type) -> KeyedEncodingContainer<Key> where Key: CodingKey {
        let newContainer = self.storage.pushKeyedContainer()
        if self.result == nil {
            self.result = newContainer
        }
        return KeyedEncodingContainer(KEC(referencing: self, container: newContainer))
    }

    struct KEC<Key: CodingKey>: KeyedEncodingContainerProtocol {
        var codingPath: [CodingKey] { self.encoder.codingPath }
        let container: _QueryEncoderKeyedContainer
        let encoder: _QueryEncoder

        /// Initialization
        /// - Parameter referencing: encoder that created this
        init(referencing: _QueryEncoder, container: _QueryEncoderKeyedContainer) {
            self.encoder = referencing
            self.container = container
        }

        mutating func encode(_ value: Any, key: String) {
            self.container.addChild(path: self.ec2Encode(key), child: value)
        }

        mutating func encodeNil(forKey key: Key) throws { self.encode("", key: key.stringValue) }
        mutating func encode(_ value: Bool, forKey key: Key) throws { self.encode(value, key: key.stringValue) }
        mutating func encode(_ value: String, forKey key: Key) throws { self.encode(value, key: key.stringValue) }
        mutating func encode(_ value: Double, forKey key: Key) throws { self.encode(value, key: key.stringValue) }
        mutating func encode(_ value: Float, forKey key: Key) throws { self.encode(value, key: key.stringValue) }
        mutating func encode(_ value: Int, forKey key: Key) throws { self.encode(value, key: key.stringValue) }
        mutating func encode(_ value: Int8, forKey key: Key) throws { self.encode(value, key: key.stringValue) }
        mutating func encode(_ value: Int16, forKey key: Key) throws { self.encode(value, key: key.stringValue) }
        mutating func encode(_ value: Int32, forKey key: Key) throws { self.encode(value, key: key.stringValue) }
        mutating func encode(_ value: Int64, forKey key: Key) throws { self.encode(value, key: key.stringValue) }
        mutating func encode(_ value: UInt, forKey key: Key) throws { self.encode(value, key: key.stringValue) }
        mutating func encode(_ value: UInt8, forKey key: Key) throws { self.encode(value, key: key.stringValue) }
        mutating func encode(_ value: UInt16, forKey key: Key) throws { self.encode(value, key: key.stringValue) }
        mutating func encode(_ value: UInt32, forKey key: Key) throws { self.encode(value, key: key.stringValue) }
        mutating func encode(_ value: UInt64, forKey key: Key) throws { self.encode(value, key: key.stringValue) }

        mutating func encode(_ value: some Encodable, forKey key: Key) throws {
            self.encoder.codingPath.append(key)
            defer { self.encoder.codingPath.removeLast() }

            let childContainer = try encoder.box(value)
            self.container.addChild(path: self.ec2Encode(key.stringValue), child: childContainer)
        }

        mutating func nestedContainer<NestedKey>(keyedBy keyType: NestedKey.Type, forKey key: Key) -> KeyedEncodingContainer<NestedKey>
        where NestedKey: CodingKey {
            self.encoder.codingPath.append(key)
            defer { self.encoder.codingPath.removeLast() }

            let keyedContainer = _QueryEncoderKeyedContainer()
            self.container.addChild(path: self.ec2Encode(key.stringValue), child: keyedContainer)

            let kec = KEC<NestedKey>(referencing: self.encoder, container: keyedContainer)
            return KeyedEncodingContainer(kec)
        }

        mutating func nestedUnkeyedContainer(forKey key: Key) -> UnkeyedEncodingContainer {
            self.encoder.codingPath.append(key)
            defer { self.encoder.codingPath.removeLast() }

            let unkeyedContainer = _QueryEncoderUnkeyedContainer()
            self.container.addChild(path: self.ec2Encode(key.stringValue), child: unkeyedContainer)

            return UKEC(referencing: self.encoder, container: unkeyedContainer)
        }

        mutating func superEncoder() -> Encoder {
            self.encoder
        }

        mutating func superEncoder(forKey key: Key) -> Encoder {
            self.encoder
        }

        func ec2Encode(_ string: String) -> String {
            if self.encoder.options.ec2 {
                return string.uppercaseFirst()
            }
            return string
        }
    }

    func unkeyedContainer() -> UnkeyedEncodingContainer {
        let container = self.storage.pushUnkeyedContainer()
        return UKEC(referencing: self, container: container)
    }

    struct UKEC: UnkeyedEncodingContainer {
        var codingPath: [CodingKey] { self.encoder.codingPath }
        let container: _QueryEncoderUnkeyedContainer
        let encoder: _QueryEncoder
        var count: Int

        init(referencing: _QueryEncoder, container: _QueryEncoderUnkeyedContainer) {
            self.encoder = referencing
            self.container = container
            self.count = 0
        }

        mutating func encodeResult(_ value: Any) {
            self.count += 1
            self.container.addChild(value)
        }

        mutating func encodeNil() throws { self.encodeResult("") }
        mutating func encode(_ value: Bool) throws { self.encodeResult(value) }
        mutating func encode(_ value: String) throws { self.encodeResult(value) }
        mutating func encode(_ value: Double) throws { self.encodeResult(value) }
        mutating func encode(_ value: Float) throws { self.encodeResult(value) }
        mutating func encode(_ value: Int) throws { self.encodeResult(value) }
        mutating func encode(_ value: Int8) throws { self.encodeResult(value) }
        mutating func encode(_ value: Int16) throws { self.encodeResult(value) }
        mutating func encode(_ value: Int32) throws { self.encodeResult(value) }
        mutating func encode(_ value: Int64) throws { self.encodeResult(value) }
        mutating func encode(_ value: UInt) throws { self.encodeResult(value) }
        mutating func encode(_ value: UInt8) throws { self.encodeResult(value) }
        mutating func encode(_ value: UInt16) throws { self.encodeResult(value) }
        mutating func encode(_ value: UInt32) throws { self.encodeResult(value) }
        mutating func encode(_ value: UInt64) throws { self.encodeResult(value) }

        mutating func encode(_ value: some Encodable) throws {
            self.count += 1

            self.encoder.codingPath.append(_QueryKey(index: self.count))
            defer { self.encoder.codingPath.removeLast() }

            let childContainer = try encoder.box(value)
            self.container.addChild(childContainer)
        }

        mutating func nestedContainer<NestedKey>(keyedBy keyType: NestedKey.Type) -> KeyedEncodingContainer<NestedKey> where NestedKey: CodingKey {
            self.count += 1

            self.encoder.codingPath.append(_QueryKey(index: self.count))
            defer { self.encoder.codingPath.removeLast() }

            let keyedContainer = _QueryEncoderKeyedContainer()
            self.container.addChild(keyedContainer)

            let kec = KEC<NestedKey>(referencing: self.encoder, container: keyedContainer)
            return KeyedEncodingContainer(kec)
        }

        mutating func nestedUnkeyedContainer() -> UnkeyedEncodingContainer {
            self.count += 1

            let unkeyedContainer = _QueryEncoderUnkeyedContainer()
            self.container.addChild(unkeyedContainer)

            return UKEC(referencing: self.encoder, container: unkeyedContainer)
        }

        mutating func superEncoder() -> Encoder {
            self.encoder
        }
    }
}

extension _QueryEncoder: SingleValueEncodingContainer {
    func encodeResult(_ value: Any) {
        self.storage.push(container: value)
    }

    func encodeNil() throws {
        self.encodeResult("")
    }

    func encode(_ value: Bool) throws { self.encodeResult(value) }
    func encode(_ value: String) throws { self.encodeResult(value) }
    func encode(_ value: Double) throws { self.encodeResult(value) }
    func encode(_ value: Float) throws { self.encodeResult(value) }
    func encode(_ value: Int) throws { self.encodeResult(value) }
    func encode(_ value: Int8) throws { self.encodeResult(value) }
    func encode(_ value: Int16) throws { self.encodeResult(value) }
    func encode(_ value: Int32) throws { self.encodeResult(value) }
    func encode(_ value: Int64) throws { self.encodeResult(value) }
    func encode(_ value: UInt) throws { self.encodeResult(value) }
    func encode(_ value: UInt8) throws { self.encodeResult(value) }
    func encode(_ value: UInt16) throws { self.encodeResult(value) }
    func encode(_ value: UInt32) throws { self.encodeResult(value) }
    func encode(_ value: UInt64) throws { self.encodeResult(value) }

    func encode(_ value: some Encodable) throws {
        try value.encode(to: self)
    }

    func singleValueContainer() -> SingleValueEncodingContainer {
        self
    }
}

extension _QueryEncoder {
    func box(_ date: Date) throws -> Any {
        try self.encode(Self.dateFormatter.string(from: date))
        return self.storage.popContainer()
    }

    func box(_ value: Encodable) throws -> Any {
        let type = Swift.type(of: value)
        if type == Date.self {
            return try self.box(value as! Date)
        } else {
            try value.encode(to: self)
            return self.storage.popContainer()
        }
    }

    nonisolated(unsafe) static let dateFormatter: ISO8601DateFormatter = {
        let dateFormatter = ISO8601DateFormatter()
        dateFormatter.formatOptions = [.withFullDate, .withFullTime, .withFractionalSeconds]
        return dateFormatter
    }()
}

//===----------------------------------------------------------------------===//
// Shared Key Types
//===----------------------------------------------------------------------===//

private struct _QueryKey: CodingKey {
    public var stringValue: String
    public var intValue: Int?

    public init?(stringValue: String) {
        self.stringValue = stringValue
        self.intValue = nil
    }

    public init?(intValue: Int) {
        self.stringValue = "\(intValue)"
        self.intValue = intValue
    }

    public init(stringValue: String, intValue: Int?) {
        self.stringValue = stringValue
        self.intValue = intValue
    }

    fileprivate init(index: Int) {
        self.stringValue = "\(index)"
        self.intValue = index
    }

    fileprivate static let `super` = _QueryKey(stringValue: "super")!
}

extension String {
    func uppercaseFirst() -> String {
        guard self.count > 0 else { return self }
        return String(self[self.startIndex]).uppercased() + self[index(after: startIndex)...]
    }
}
