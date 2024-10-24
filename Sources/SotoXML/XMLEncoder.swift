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

import struct Foundation.Data
import struct Foundation.Date
import class Foundation.ISO8601DateFormatter
import struct Foundation.URL

/// The wrapper class for encoding Codable classes to XMLElements
public struct XMLEncoder {
    /// The strategy to use for encoding `Data` values.
    public enum DataEncodingStrategy {
        /// Encoded the `Data` as a Base64-encoded string. This is the default strategy.
        case base64

        /// Encode the `Data` as a custom value encoded by the given closure.
        ///
        /// If the closure fails to encode a value into the given encoder, the encoder will encode an empty automatic container in its place.
        case custom((Data, Encoder) throws -> XML.Element)
    }

    /// The strategy to use for non-JSON-conforming floating-point values (IEEE 754 infinity and NaN).
    public enum NonConformingFloatEncodingStrategy {
        /// Throw upon encountering non-conforming values. This is the default strategy.
        case `throw`

        /// Encode the values using the given representation strings.
        case convertToString(positiveInfinity: String, negativeInfinity: String, nan: String)
    }

    /// The strategy to use in encoding binary data. Defaults to `.base64`.
    public var dataEncodingStrategy: DataEncodingStrategy = .base64

    /// The strategy to use in encoding non-conforming numbers. Defaults to `.throw`.
    public var nonConformingFloatEncodingStrategy: NonConformingFloatEncodingStrategy = .throw

    /// Contextual user-provided information for use during encoding.
    public var userInfo: [CodingUserInfoKey: Any] = [:]

    /// Options set on the top-level encoder to pass down the encoding hierarchy.
    fileprivate struct _Options {
        let dataEncodingStrategy: DataEncodingStrategy
        let nonConformingFloatEncodingStrategy: NonConformingFloatEncodingStrategy
        let userInfo: [CodingUserInfoKey: Any]
    }

    /// The options set on the top-level encoder.
    fileprivate var options: _Options {
        return _Options(
            dataEncodingStrategy: self.dataEncodingStrategy,
            nonConformingFloatEncodingStrategy: self.nonConformingFloatEncodingStrategy,
            userInfo: self.userInfo
        )
    }

    public init() {}

    public func encode(_ value: some Encodable, name: String? = nil) throws -> XML.Element? {
        let rootName = name ?? "\(type(of: value))"
        let encoder = _XMLEncoder(options: options, codingPath: [_XMLKey(stringValue: rootName, intValue: nil)])
        try value.encode(to: encoder)
        return encoder.element
    }
}

/// storage for XML Encoder. Stores a stack of XMLElements
struct _XMLEncoderStorage {
    /// the container stack
    private var containers: [XML.Element?] = []

    /// initializes self with no containers
    init() {}

    /// return the container at the top of the storage
    var topContainer: XML.Element? { return self.containers.last ?? nil }

    /// push a new container onto the storage
    mutating func push(container: XML.Element?) { self.containers.append(container) }

    /// pop a container from the storage
    @discardableResult mutating func popContainer() -> XML.Element? {
        if self.containers.count > 0 {
            return self.containers.removeLast()
        } else {
            return nil
        }
    }
}

/// Internal XMLEncoder class. Does all the heavy lifting
class _XMLEncoder: Encoder {
    // MARK: Properties

    /// the encoder's storage
    var storage: _XMLEncoderStorage

    /// Options set on the top-level encoder.
    fileprivate let options: XMLEncoder._Options

    /// the path to the current point in encoding
    var codingPath: [CodingKey]

    /// contextual user-provided information for use during encoding
    var userInfo: [CodingUserInfoKey: Any] { return self.options.userInfo }

    /// the top level key
    var currentKey: String { return self.codingPath.last!.stringValue }

    /// the top level xml element
    var element: XML.Element? { return self.storage.topContainer }

    // MARK: - Initialization

    fileprivate init(options: XMLEncoder._Options, codingPath: [CodingKey] = []) {
        self.storage = _XMLEncoderStorage()
        self.options = options
        self.codingPath = codingPath
    }

    // MARK: - Encoder methods

    func container<Key>(keyedBy type: Key.Type) -> KeyedEncodingContainer<Key> where Key: CodingKey {
        let newElement = XML.Element(name: self.currentKey)
        self.storage.push(container: newElement)
        return KeyedEncodingContainer(KEC(newElement, referencing: self))
    }

    struct KEC<Key: CodingKey>: KeyedEncodingContainerProtocol {
        let encoder: _XMLEncoder
        let element: XML.Element
        var codingPath: [CodingKey] { return self.encoder.codingPath }

        init(_ element: XML.Element, referencing encoder: _XMLEncoder) {
            self.element = element
            self.encoder = encoder
        }

        func encodeNil(forKey key: Key) throws {}

        func encode(_ value: Bool, forKey key: Key) throws {
            let childElement = XML.Element(name: key.stringValue, stringValue: self.encoder.box(value))
            self.element.addChild(childElement)
        }

        func encode(_ value: String, forKey key: Key) throws {
            let childElement = XML.Element(name: key.stringValue, stringValue: self.encoder.box(value))
            self.element.addChild(childElement)
        }

        func encode(_ value: Int, forKey key: Key) throws {
            let childElement = XML.Element(name: key.stringValue, stringValue: self.encoder.box(value))
            self.element.addChild(childElement)
        }

        func encode(_ value: Int8, forKey key: Key) throws {
            let childElement = XML.Element(name: key.stringValue, stringValue: self.encoder.box(value))
            self.element.addChild(childElement)
        }

        func encode(_ value: Int16, forKey key: Key) throws {
            let childElement = XML.Element(name: key.stringValue, stringValue: self.encoder.box(value))
            self.element.addChild(childElement)
        }

        func encode(_ value: Int32, forKey key: Key) throws {
            let childElement = XML.Element(name: key.stringValue, stringValue: self.encoder.box(value))
            self.element.addChild(childElement)
        }

        func encode(_ value: Int64, forKey key: Key) throws {
            let childElement = XML.Element(name: key.stringValue, stringValue: self.encoder.box(value))
            self.element.addChild(childElement)
        }

        func encode(_ value: UInt, forKey key: Key) throws {
            let childElement = XML.Element(name: key.stringValue, stringValue: self.encoder.box(value))
            self.element.addChild(childElement)
        }

        func encode(_ value: UInt8, forKey key: Key) throws {
            let childElement = XML.Element(name: key.stringValue, stringValue: self.encoder.box(value))
            self.element.addChild(childElement)
        }

        func encode(_ value: UInt16, forKey key: Key) throws {
            let childElement = XML.Element(name: key.stringValue, stringValue: self.encoder.box(value))
            self.element.addChild(childElement)
        }

        func encode(_ value: UInt32, forKey key: Key) throws {
            let childElement = XML.Element(name: key.stringValue, stringValue: self.encoder.box(value))
            self.element.addChild(childElement)
        }

        func encode(_ value: UInt64, forKey key: Key) throws {
            let childElement = XML.Element(name: key.stringValue, stringValue: self.encoder.box(value))
            self.element.addChild(childElement)
        }

        func encode(_ value: Double, forKey key: Key) throws {
            let childElement = try XML.Element(name: key.stringValue, stringValue: self.encoder.box(value))
            self.element.addChild(childElement)
        }

        func encode(_ value: Float, forKey key: Key) throws {
            let childElement = try XML.Element(name: key.stringValue, stringValue: self.encoder.box(value))
            self.element.addChild(childElement)
        }

        func encode(_ value: some Encodable, forKey key: Key) throws {
            // get element to attach child elements, also what to name those elements
            self.encoder.codingPath.append(key)
            defer { self.encoder.codingPath.removeLast() }

            if let childElement = try encoder.box(value) {
                if self.element !== childElement {
                    self.element.addChild(childElement)
                }
            }
        }

        func nestedContainer<NestedKey>(keyedBy keyType: NestedKey.Type, forKey key: Key) -> KeyedEncodingContainer<NestedKey> where NestedKey: CodingKey {
            self.encoder.codingPath.append(key)
            defer { self.encoder.codingPath.removeLast() }

            let newElement = XML.Element(name: key.stringValue)
            self.element.addChild(newElement)

            let container = KEC<NestedKey>(newElement, referencing: self.encoder)

            return KeyedEncodingContainer(container)
        }

        func nestedUnkeyedContainer(forKey key: Key) -> UnkeyedEncodingContainer {
            self.encoder.codingPath.append(key)
            defer { self.encoder.codingPath.removeLast() }

            return UKEC(self.element, referencing: self.encoder)
        }

        func superEncoder() -> Encoder {
            return _XMLReferencingEncoder(referencing: self.encoder, key: _XMLKey.super, wrapping: self.element)
        }

        func superEncoder(forKey key: Key) -> Encoder {
            return _XMLReferencingEncoder(referencing: self.encoder, key: key, wrapping: self.element)
        }
    }

    func unkeyedContainer() -> UnkeyedEncodingContainer {
        self.storage.push(container: self.element!)
        return UKEC(self.element!, referencing: self)
    }

    struct UKEC: UnkeyedEncodingContainer {
        let encoder: _XMLEncoder
        let element: XML.Element
        var codingPath: [CodingKey] { return self.encoder.codingPath }
        var count: Int
        let key: String

        init(_ element: XML.Element, referencing encoder: _XMLEncoder) {
            self.element = element
            self.encoder = encoder
            self.count = 0
            self.key = encoder.currentKey
        }

        mutating func encode(_ value: Bool) throws {
            let childElement = XML.Element(name: self.key, stringValue: self.encoder.box(value))
            self.element.addChild(childElement)
            self.count += 1
        }

        mutating func encodeNil() throws {
            self.count += 1
        }

        mutating func encode(_ value: String) throws {
            let childElement = XML.Element(name: self.key, stringValue: self.encoder.box(value))
            self.element.addChild(childElement)
            self.count += 1
        }

        mutating func encode(_ value: Int) throws {
            let childElement = XML.Element(name: self.key, stringValue: self.encoder.box(value))
            self.element.addChild(childElement)
            self.count += 1
        }

        mutating func encode(_ value: Int8) throws {
            let childElement = XML.Element(name: self.key, stringValue: self.encoder.box(value))
            self.element.addChild(childElement)
            self.count += 1
        }

        mutating func encode(_ value: Int16) throws {
            let childElement = XML.Element(name: self.key, stringValue: self.encoder.box(value))
            self.element.addChild(childElement)
            self.count += 1
        }

        mutating func encode(_ value: Int32) throws {
            let childElement = XML.Element(name: self.key, stringValue: self.encoder.box(value))
            self.element.addChild(childElement)
            self.count += 1
        }

        mutating func encode(_ value: Int64) throws {
            let childElement = XML.Element(name: self.key, stringValue: self.encoder.box(value))
            self.element.addChild(childElement)
            self.count += 1
        }

        mutating func encode(_ value: UInt) throws {
            let childElement = XML.Element(name: self.key, stringValue: self.encoder.box(value))
            self.element.addChild(childElement)
            self.count += 1
        }

        mutating func encode(_ value: UInt8) throws {
            let childElement = XML.Element(name: self.key, stringValue: self.encoder.box(value))
            self.element.addChild(childElement)
            self.count += 1
        }

        mutating func encode(_ value: UInt16) throws {
            let childElement = XML.Element(name: self.key, stringValue: self.encoder.box(value))
            self.element.addChild(childElement)
            self.count += 1
        }

        mutating func encode(_ value: UInt32) throws {
            let childElement = XML.Element(name: self.key, stringValue: self.encoder.box(value))
            self.element.addChild(childElement)
            self.count += 1
        }

        mutating func encode(_ value: UInt64) throws {
            let childElement = XML.Element(name: self.key, stringValue: self.encoder.box(value))
            self.element.addChild(childElement)
            self.count += 1
        }

        mutating func encode(_ value: Double) throws {
            let childElement = try XML.Element(name: self.key, stringValue: self.encoder.box(value))
            self.element.addChild(childElement)
            self.count += 1
        }

        mutating func encode(_ value: Float) throws {
            let childElement = try XML.Element(name: self.key, stringValue: self.encoder.box(value))
            self.element.addChild(childElement)
            self.count += 1
        }

        mutating func encode(_ value: some Encodable) throws {
            self.encoder.codingPath.append(_XMLKey(stringValue: self.key, intValue: self.count))
            defer { self.encoder.codingPath.removeLast() }

            if let childElement = try encoder.box(value) {
                if self.element !== childElement {
                    self.element.addChild(childElement)
                }
            }
            self.count += 1
        }

        mutating func nestedContainer<NestedKey>(keyedBy keyType: NestedKey.Type) -> KeyedEncodingContainer<NestedKey> where NestedKey: CodingKey {
            self.encoder.codingPath.append(_XMLKey(stringValue: self.key, intValue: self.count))
            defer { self.encoder.codingPath.removeLast() }

            let newElement = XML.Element(name: self.key)
            self.element.addChild(newElement)

            self.count += 1

            let container = KEC<NestedKey>(newElement, referencing: self.encoder)
            return KeyedEncodingContainer(container)
        }

        mutating func nestedUnkeyedContainer() -> UnkeyedEncodingContainer {
            self.count += 1

            return UKEC(self.element, referencing: self.encoder)
        }

        func superEncoder() -> Encoder {
            return _XMLReferencingEncoder(referencing: self.encoder, key: _XMLKey.super, wrapping: self.element)
        }
    }

    func singleValueContainer() -> SingleValueEncodingContainer {
        return self
    }
}

extension _XMLEncoder: SingleValueEncodingContainer {
    func encodeNil() throws {
        self.storage.push(container: nil)
    }

    func encode(_ value: Bool) throws {
        self.storage.push(container: XML.Element(name: self.currentKey, stringValue: box(value)))
    }

    func encode(_ value: String) throws {
        self.storage.push(container: XML.Element(name: self.currentKey, stringValue: box(value)))
    }

    func encode(_ value: Int) throws {
        self.storage.push(container: XML.Element(name: self.currentKey, stringValue: box(value)))
    }

    func encode(_ value: Int8) throws {
        self.storage.push(container: XML.Element(name: self.currentKey, stringValue: box(value)))
    }

    func encode(_ value: Int16) throws {
        self.storage.push(container: XML.Element(name: self.currentKey, stringValue: box(value)))
    }

    func encode(_ value: Int32) throws {
        self.storage.push(container: XML.Element(name: self.currentKey, stringValue: box(value)))
    }

    func encode(_ value: Int64) throws {
        self.storage.push(container: XML.Element(name: self.currentKey, stringValue: box(value)))
    }

    func encode(_ value: UInt) throws {
        self.storage.push(container: XML.Element(name: self.currentKey, stringValue: box(value)))
    }

    func encode(_ value: UInt8) throws {
        self.storage.push(container: XML.Element(name: self.currentKey, stringValue: box(value)))
    }

    func encode(_ value: UInt16) throws {
        self.storage.push(container: XML.Element(name: self.currentKey, stringValue: box(value)))
    }

    func encode(_ value: UInt32) throws {
        self.storage.push(container: XML.Element(name: self.currentKey, stringValue: box(value)))
    }

    func encode(_ value: UInt64) throws {
        self.storage.push(container: XML.Element(name: self.currentKey, stringValue: box(value)))
    }

    func encode(_ value: Double) throws {
        try self.storage.push(container: XML.Element(name: self.currentKey, stringValue: box(value)))
    }

    func encode(_ value: Float) throws {
        try self.storage.push(container: XML.Element(name: self.currentKey, stringValue: box(value)))
    }

    func encode(_ value: some Encodable) throws {
        try self.storage.push(container: box(value))
    }
}

extension _XMLEncoder {
    /// Returns the given value boxed in a container appropriate for pushing onto the container stack.
    private func box(_ value: Bool) -> String { return value.description }
    private func box(_ value: Int) -> String { return value.description }
    private func box(_ value: Int8) -> String { return value.description }
    private func box(_ value: Int16) -> String { return value.description }
    private func box(_ value: Int32) -> String { return value.description }
    private func box(_ value: Int64) -> String { return value.description }
    private func box(_ value: UInt) -> String { return value.description }
    private func box(_ value: UInt8) -> String { return value.description }
    private func box(_ value: UInt16) -> String { return value.description }
    private func box(_ value: UInt32) -> String { return value.description }
    private func box(_ value: UInt64) -> String { return value.description }
    private func box(_ value: String) -> String { return value }

    private func box(_ float: Float) throws -> String {
        guard !float.isInfinite, !float.isNaN else {
            guard case .convertToString(
                positiveInfinity: let posInfString,
                negativeInfinity: let negInfString,
                nan: let nanString
            ) = self.options.nonConformingFloatEncodingStrategy
            else {
                throw EncodingError._invalidFloatingPointValue(float, at: self.codingPath)
            }

            if float == Float.infinity {
                return posInfString
            } else if float == -Float.infinity {
                return negInfString
            } else {
                return nanString
            }
        }

        return float.description
    }

    private func box(_ double: Double) throws -> String {
        guard !double.isInfinite, !double.isNaN else {
            guard case .convertToString(
                positiveInfinity: let posInfString,
                negativeInfinity: let negInfString,
                nan: let nanString
            ) = self.options.nonConformingFloatEncodingStrategy
            else {
                throw EncodingError._invalidFloatingPointValue(double, at: self.codingPath)
            }

            if double == Double.infinity {
                return posInfString
            } else if double == -Double.infinity {
                return negInfString
            } else {
                return nanString
            }
        }

        return double.description
    }

    func box(_ date: Date) throws -> XML.Element? {
        return XML.Element(name: self.currentKey, stringValue: Self.dateFormatter.string(from: date))
    }

    func box(_ data: Data) throws -> XML.Element? {
        switch self.options.dataEncodingStrategy {
        case .base64:
            return XML.Element(name: self.currentKey, stringValue: data.base64EncodedString())

        case .custom(let closure):
            return try closure(data, self)
        }
    }

    func box(_ value: Encodable) throws -> XML.Element? {
        let type = Swift.type(of: value)

        if type == Data.self {
            return try self.box(value as! Data)
        } else if type == Date.self {
            return try self.box(value as! Date)
        } else {
            try value.encode(to: self)
            return self.storage.popContainer()
        }
    }

    #if compiler(>=5.10)
    nonisolated(unsafe) static let dateFormatter: ISO8601DateFormatter = {
        let dateFormatter = ISO8601DateFormatter()
        dateFormatter.formatOptions = [.withFullDate, .withFullTime, .withFractionalSeconds]
        return dateFormatter
    }()
    #else
    static let dateFormatter: ISO8601DateFormatter = {
        let dateFormatter = ISO8601DateFormatter()
        dateFormatter.formatOptions = [.withFullDate, .withFullTime, .withFractionalSeconds]
        return dateFormatter
    }()
    #endif
}

// MARK: - _XMLReferencingEncoder

/// _XMLReferencingEncoder is a special subclass of _XMLEncoder which has its own storage, but references the contents of a different encoder.
/// It's used in superEncoder(), which returns a new encoder for encoding a superclass -- the lifetime of the encoder should not escape the scope it's created in, but it doesn't necessarily know when it's done being used (to write to the original container).
private class _XMLReferencingEncoder: _XMLEncoder {
    // MARK: - Properties

    /// The encoder we're referencing.
    fileprivate let encoder: _XMLEncoder

    /// The container reference itself.
    private let reference: XML.Element

    // MARK: - Initialization

    /// Initializes `self` by referencing the given array container in the given encoder.
    fileprivate init(referencing encoder: _XMLEncoder, key: CodingKey, wrapping element: XML.Element) {
        self.encoder = encoder
        self.reference = element
        super.init(options: encoder.options, codingPath: encoder.codingPath)

        self.codingPath.append(key)
    }

    // MARK: - Coding Path Operations

    // MARK: - Deinitialization

    // Finalizes `self` by writing the contents of our storage to the referenced encoder's storage.
    deinit {
        if let element {
            reference.addChild(element)
        }
    }
}

//===----------------------------------------------------------------------===//
// Shared Key Types
//===----------------------------------------------------------------------===//

private struct _XMLKey: CodingKey {
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
        self.stringValue = "Index \(index)"
        self.intValue = index
    }

    fileprivate static let `super` = _XMLKey(stringValue: "super")!
}

//===----------------------------------------------------------------------===//
// Error Utilities
//===----------------------------------------------------------------------===//

extension EncodingError {
    /// Returns a `.invalidValue` error describing the given invalid floating-point value.
    ///
    ///
    /// - parameter value: The value that was invalid to encode.
    /// - parameter path: The path of `CodingKey`s taken to encode this value.
    /// - returns: An `EncodingError` with the appropriate path and debug description.
    fileprivate static func _invalidFloatingPointValue<T: FloatingPoint>(_ value: T, at codingPath: [CodingKey]) -> EncodingError {
        let valueDescription: String
        if value == T.infinity {
            valueDescription = "\(T.self).infinity"
        } else if value == -T.infinity {
            valueDescription = "-\(T.self).infinity"
        } else {
            valueDescription = "\(T.self).nan"
        }

        let debugDescription = "Unable to encode \(valueDescription) directly. Use DictionaryEncoder.NonConformingFloatEncodingStrategy.convertToString to specify how the value should be encoded."
        return .invalidValue(value, EncodingError.Context(codingPath: codingPath, debugDescription: debugDescription))
    }
}
