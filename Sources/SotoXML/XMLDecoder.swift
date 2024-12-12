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
import class Foundation.NSNull
import class Foundation.NSNumber
import struct Foundation.URL

/// The wrapper class for decoding Codable classes from XMLNodes
public struct XMLDecoder {
    /// The strategy to use for decoding `Data` values.
    public enum DataDecodingStrategy {
        /// Decode the `Data` from a Base64-encoded string.
        case base64

        /// Decode the `Data` as a custom value decoded by the given closure.
        case custom((_ decoder: Decoder) throws -> Data)
    }

    /// The strategy to use for non-JSON-conforming floating-point values (IEEE 754 infinity and NaN).
    public enum NonConformingFloatDecodingStrategy {
        /// Throw upon encountering non-conforming values. This is the default strategy.
        case `throw`

        /// Decode the values from the given representation strings.
        case convertFromString(positiveInfinity: String, negativeInfinity: String, nan: String)
    }

    /// The strategy to use in decoding binary data. Defaults to `.raw`.
    public var dataDecodingStrategy: DataDecodingStrategy = .base64

    /// The strategy to use in decoding non-conforming numbers. Defaults to `.throw`.
    public var nonConformingFloatDecodingStrategy: NonConformingFloatDecodingStrategy = .throw

    /// Contextual user-provided information for use during decoding.
    public var userInfo: [CodingUserInfoKey: Any] = [:]

    /// Options set on the top-level encoder to pass down the decoding hierarchy.
    fileprivate struct _Options {
        let dataDecodingStrategy: DataDecodingStrategy
        let nonConformingFloatDecodingStrategy: NonConformingFloatDecodingStrategy
        let userInfo: [CodingUserInfoKey: Any]
    }

    /// The options set on the top-level decoder.
    fileprivate var options: _Options {
        _Options(
            dataDecodingStrategy: self.dataDecodingStrategy,
            nonConformingFloatDecodingStrategy: self.nonConformingFloatDecodingStrategy,
            userInfo: self.userInfo
        )
    }

    public init() {}

    /// decode a Codable class from XML
    public func decode<T: Decodable>(_ type: T.Type, from xml: XML.Node) throws -> T {
        let decoder = _XMLDecoder(xml, options: self.options)
        let value = try T(from: decoder)
        return value
    }
}

extension XML.Node {
    func child(for string: String) -> XML.Node? {
        (children ?? []).first(where: { $0.name == string })
    }

    func child(for key: CodingKey) -> XML.Node? {
        self.child(for: key.stringValue)
    }
}

extension XML.Element {
    func attribute(for key: CodingKey) -> XML.Node? {
        self.attribute(forName: key.stringValue)
    }
}

/// Storage for the XMLDecoder. Stores a stack of XMLNodes
struct _XMLDecoderStorage {
    /// the container stack
    private var containers: [XML.Node?] = []

    /// initializes self with no containers
    init() {}

    /// return the container at the top of the storage
    var topContainer: XML.Node? { self.containers.last! }

    /// push a new container onto the storage
    mutating func push(container: XML.Node?) { self.containers.append(container) }

    /// pop a container from the storage
    @discardableResult mutating func popContainer() -> XML.Node? { self.containers.removeLast() }
}

/// Internal XMLDecoder class. Does all the heavy lifting
private class _XMLDecoder: Decoder {
    /// The decoder's storage.
    var storage: _XMLDecoderStorage

    /// Options set on the top-level decoder.
    let options: XMLDecoder._Options

    /// The path to the current point in encoding.
    var codingPath: [CodingKey]

    /// Contextual user-provided information for use during encoding.
    public var userInfo: [CodingUserInfoKey: Any] { self.options.userInfo }

    public init(_ element: XML.Node, at codingPath: [CodingKey] = [], options: XMLDecoder._Options) {
        self.storage = _XMLDecoderStorage()
        self.storage.push(container: element)
        self.codingPath = codingPath
        self.options = options
    }

    public func container<Key>(keyedBy type: Key.Type) throws -> KeyedDecodingContainer<Key> where Key: CodingKey {
        guard let element = storage.topContainer else {
            throw DecodingError.keyNotFound(
                self.codingPath.last!,
                DecodingError.Context(codingPath: self.codingPath, debugDescription: "Key not found")
            )
        }
        return KeyedDecodingContainer(KDC(element, decoder: self))
    }

    struct KDC<Key: CodingKey>: KeyedDecodingContainerProtocol {
        var codingPath: [CodingKey] { self.decoder.codingPath }
        var allKeys: [Key] = []
        let element: XML.Node
        let decoder: _XMLDecoder

        public init(_ element: XML.Node, decoder: _XMLDecoder) {
            self.element = element
            self.decoder = decoder

            // all elements directly under the container xml element are considered. THe key is the name of the element and the value is the text attached to the element
            self.allKeys =
                element.children?.compactMap { (element: XML.Node) -> Key? in
                    if let name = element.name {
                        return Key(stringValue: name)
                    }
                    return nil
                } ?? []
        }

        /// return if decoder has a value for a key
        func contains(_ key: Key) -> Bool {
            self.element.child(for: key) != nil
        }

        /// get the XMLElment for a particular key
        func child(for key: CodingKey) throws -> XML.Node {
            if let child = element.child(for: key) {
                return child
            } else if let attribute = (element as? XML.Element)?.attribute(for: key) {
                return attribute
            }
            throw DecodingError.keyNotFound(key, DecodingError.Context(codingPath: self.codingPath, debugDescription: "Key not found"))
        }

        /// get the XMLElment for a particular key
        func optionalChild(for key: CodingKey) -> XML.Node? {
            if let child = element.child(for: key) {
                return child
            } else if let attribute = (element as? XML.Element)?.attribute(for: key) {
                return attribute
            }
            return nil
        }

        func decodeNil(forKey key: Key) throws -> Bool {
            // let child = try self.child(for: key)
            false
        }

        func decode(_ type: Bool.Type, forKey key: Key) throws -> Bool {
            let child = try self.child(for: key)
            return try self.decoder.unbox(child, as: Bool.self)
        }

        func decode(_ type: String.Type, forKey key: Key) throws -> String {
            let child = try self.child(for: key)
            return try self.decoder.unbox(child, as: String.self)
        }

        func decode(_ type: Double.Type, forKey key: Key) throws -> Double {
            let child = try self.child(for: key)
            return try self.decoder.unbox(child, as: Double.self)
        }

        func decode(_ type: Float.Type, forKey key: Key) throws -> Float {
            let child = try self.child(for: key)
            return try self.decoder.unbox(child, as: Float.self)
        }

        func decode(_ type: Int.Type, forKey key: Key) throws -> Int {
            let child = try self.child(for: key)
            return try self.decoder.unbox(child, as: Int.self)
        }

        func decode(_ type: Int8.Type, forKey key: Key) throws -> Int8 {
            let child = try self.child(for: key)
            return try self.decoder.unbox(child, as: Int8.self)
        }

        func decode(_ type: Int16.Type, forKey key: Key) throws -> Int16 {
            let child = try self.child(for: key)
            return try self.decoder.unbox(child, as: Int16.self)
        }

        func decode(_ type: Int32.Type, forKey key: Key) throws -> Int32 {
            let child = try self.child(for: key)
            return try self.decoder.unbox(child, as: Int32.self)
        }

        func decode(_ type: Int64.Type, forKey key: Key) throws -> Int64 {
            let child = try self.child(for: key)
            return try self.decoder.unbox(child, as: Int64.self)
        }

        func decode(_ type: UInt.Type, forKey key: Key) throws -> UInt {
            let child = try self.child(for: key)
            return try self.decoder.unbox(child, as: UInt.self)
        }

        func decode(_ type: UInt8.Type, forKey key: Key) throws -> UInt8 {
            let child = try self.child(for: key)
            return try self.decoder.unbox(child, as: UInt8.self)
        }

        func decode(_ type: UInt16.Type, forKey key: Key) throws -> UInt16 {
            let child = try self.child(for: key)
            return try self.decoder.unbox(child, as: UInt16.self)
        }

        func decode(_ type: UInt32.Type, forKey key: Key) throws -> UInt32 {
            let child = try self.child(for: key)
            return try self.decoder.unbox(child, as: UInt32.self)
        }

        func decode(_ type: UInt64.Type, forKey key: Key) throws -> UInt64 {
            let child = try self.child(for: key)
            return try self.decoder.unbox(child, as: UInt64.self)
        }

        func decode<T>(_ type: T.Type, forKey key: Key) throws -> T where T: Decodable {
            self.decoder.codingPath.append(key)
            defer { self.decoder.codingPath.removeLast() }

            let element = self.optionalChild(for: key)
            return try self.decoder.unbox(element, as: T.self)
        }

        func nestedContainer<NestedKey>(keyedBy type: NestedKey.Type, forKey key: Key) throws -> KeyedDecodingContainer<NestedKey>
        where NestedKey: CodingKey {
            self.decoder.codingPath.append(key)
            defer { self.decoder.codingPath.removeLast() }

            let child = try self.child(for: key)

            let container = KDC<NestedKey>(child, decoder: self.decoder)
            return KeyedDecodingContainer(container)
        }

        func nestedUnkeyedContainer(forKey key: Key) throws -> UnkeyedDecodingContainer {
            self.decoder.codingPath.append(key)
            defer { self.decoder.codingPath.removeLast() }

            return UKDC(self.element, decoder: self.decoder)
        }

        private func _superDecoder(forKey key: __owned CodingKey) throws -> Decoder {
            self.decoder.codingPath.append(key)
            defer { self.decoder.codingPath.removeLast() }

            let child = try self.child(for: key)
            return _XMLDecoder(child, at: self.decoder.codingPath, options: self.decoder.options)
        }

        func superDecoder() throws -> Decoder {
            try self._superDecoder(forKey: _XMLKey.super)
        }

        func superDecoder(forKey key: Key) throws -> Decoder {
            try self._superDecoder(forKey: key)
        }
    }

    public func unkeyedContainer() throws -> UnkeyedDecodingContainer {
        let top = self.storage.popContainer()
        defer {
            storage.push(container: top)
        }
        guard let element = storage.topContainer else {
            throw DecodingError.keyNotFound(
                self.codingPath.last!,
                DecodingError.Context(codingPath: self.codingPath, debugDescription: "Key not found")
            )
        }
        return UKDC(element, decoder: self)
    }

    struct UKDC: UnkeyedDecodingContainer {
        var codingPath: [CodingKey] { self.decoder.codingPath }
        var currentIndex: Int = 0
        let elements: [XML.Node]
        let decoder: _XMLDecoder

        init(_ element: XML.Node, decoder: _XMLDecoder) {
            self.elements = (element as? XML.Element)?.elements(forName: decoder.codingPath.last!.stringValue) ?? []
            self.decoder = decoder
        }

        var count: Int? {
            self.elements.count
        }

        var isAtEnd: Bool {
            self.currentIndex >= self.count!
        }

        mutating func decodeNil() throws -> Bool {
            fatalError()
        }

        mutating func decode(_: Bool.Type) throws -> Bool {
            let value = try decoder.unbox(self.elements[self.currentIndex], as: Bool.self)
            self.currentIndex += 1
            return value
        }

        mutating func decode(_: String.Type) throws -> String {
            let value = try decoder.unbox(self.elements[self.currentIndex], as: String.self)
            self.currentIndex += 1
            return value
        }

        mutating func decode(_: Double.Type) throws -> Double {
            let value = try decoder.unbox(self.elements[self.currentIndex], as: Double.self)
            self.currentIndex += 1
            return value
        }

        mutating func decode(_: Float.Type) throws -> Float {
            let value = try decoder.unbox(self.elements[self.currentIndex], as: Float.self)
            self.currentIndex += 1
            return value
        }

        mutating func decode(_: Int.Type) throws -> Int {
            let value = try decoder.unbox(self.elements[self.currentIndex], as: Int.self)
            self.currentIndex += 1
            return value
        }

        mutating func decode(_: Int8.Type) throws -> Int8 {
            let value = try decoder.unbox(self.elements[self.currentIndex], as: Int8.self)
            self.currentIndex += 1
            return value
        }

        mutating func decode(_: Int16.Type) throws -> Int16 {
            let value = try decoder.unbox(self.elements[self.currentIndex], as: Int16.self)
            self.currentIndex += 1
            return value
        }

        mutating func decode(_: Int32.Type) throws -> Int32 {
            let value = try decoder.unbox(self.elements[self.currentIndex], as: Int32.self)
            self.currentIndex += 1
            return value
        }

        mutating func decode(_: Int64.Type) throws -> Int64 {
            let value = try decoder.unbox(self.elements[self.currentIndex], as: Int64.self)
            self.currentIndex += 1
            return value
        }

        mutating func decode(_: UInt.Type) throws -> UInt {
            let value = try decoder.unbox(self.elements[self.currentIndex], as: UInt.self)
            self.currentIndex += 1
            return value
        }

        mutating func decode(_: UInt8.Type) throws -> UInt8 {
            let value = try decoder.unbox(self.elements[self.currentIndex], as: UInt8.self)
            self.currentIndex += 1
            return value
        }

        mutating func decode(_: UInt16.Type) throws -> UInt16 {
            let value = try decoder.unbox(self.elements[self.currentIndex], as: UInt16.self)
            self.currentIndex += 1
            return value
        }

        mutating func decode(_: UInt32.Type) throws -> UInt32 {
            let value = try decoder.unbox(self.elements[self.currentIndex], as: UInt32.self)
            self.currentIndex += 1
            return value
        }

        mutating func decode(_: UInt64.Type) throws -> UInt64 {
            let value = try decoder.unbox(self.elements[self.currentIndex], as: UInt64.self)
            self.currentIndex += 1
            return value
        }

        mutating func decode<T>(_: T.Type) throws -> T where T: Decodable {
            let value = try decoder.unbox(self.elements[self.currentIndex], as: T.self)
            self.currentIndex += 1
            return value
        }

        mutating func nestedContainer<NestedKey>(keyedBy type: NestedKey.Type) throws -> KeyedDecodingContainer<NestedKey>
        where NestedKey: CodingKey {
            self.decoder.codingPath.append(_XMLKey(index: self.currentIndex))
            defer { self.decoder.codingPath.removeLast() }

            let child = self.elements[self.currentIndex]
            self.currentIndex += 1

            let container = KDC<NestedKey>(child, decoder: self.decoder)
            return KeyedDecodingContainer(container)
        }

        mutating func nestedUnkeyedContainer() throws -> UnkeyedDecodingContainer {
            self.decoder.codingPath.append(_XMLKey(index: self.currentIndex))
            defer { self.decoder.codingPath.removeLast() }

            self.currentIndex += 1

            return UKDC(self.elements[self.currentIndex], decoder: self.decoder)
        }

        mutating func superDecoder() throws -> Decoder {
            self.decoder.codingPath.append(_XMLKey(index: self.currentIndex))
            defer { self.decoder.codingPath.removeLast() }

            let child = self.elements[self.currentIndex]
            self.currentIndex += 1

            return _XMLDecoder(child, at: self.decoder.codingPath, options: self.decoder.options)
        }
    }

    public func singleValueContainer() throws -> SingleValueDecodingContainer {
        guard let element = storage.topContainer else {
            throw DecodingError.keyNotFound(
                self.codingPath.last!,
                DecodingError.Context(codingPath: self.codingPath, debugDescription: "Key not found")
            )
        }
        return SVDC(element, decoder: self)
    }

    struct SVDC: SingleValueDecodingContainer {
        var codingPath: [CodingKey] { self.decoder.codingPath }
        let element: XML.Node
        let decoder: _XMLDecoder

        init(_ element: XML.Node, decoder: _XMLDecoder) {
            self.element = element
            self.decoder = decoder
        }

        func decodeNil() -> Bool {
            fatalError()
        }

        func decode(_: Bool.Type) throws -> Bool {
            try self.decoder.unbox(self.element, as: Bool.self)
        }

        func decode(_: String.Type) throws -> String {
            try self.decoder.unbox(self.element, as: String.self)
        }

        func decode(_: Double.Type) throws -> Double {
            try self.decoder.unbox(self.element, as: Double.self)
        }

        func decode(_: Float.Type) throws -> Float {
            try self.decoder.unbox(self.element, as: Float.self)
        }

        func decode(_: Int.Type) throws -> Int {
            try self.decoder.unbox(self.element, as: Int.self)
        }

        func decode(_: Int8.Type) throws -> Int8 {
            try self.decoder.unbox(self.element, as: Int8.self)
        }

        func decode(_: Int16.Type) throws -> Int16 {
            try self.decoder.unbox(self.element, as: Int16.self)
        }

        func decode(_: Int32.Type) throws -> Int32 {
            try self.decoder.unbox(self.element, as: Int32.self)
        }

        func decode(_: Int64.Type) throws -> Int64 {
            try self.decoder.unbox(self.element, as: Int64.self)
        }

        func decode(_: UInt.Type) throws -> UInt {
            try self.decoder.unbox(self.element, as: UInt.self)
        }

        func decode(_: UInt8.Type) throws -> UInt8 {
            try self.decoder.unbox(self.element, as: UInt8.self)
        }

        func decode(_: UInt16.Type) throws -> UInt16 {
            try self.decoder.unbox(self.element, as: UInt16.self)
        }

        func decode(_: UInt32.Type) throws -> UInt32 {
            try self.decoder.unbox(self.element, as: UInt32.self)
        }

        func decode(_: UInt64.Type) throws -> UInt64 {
            try self.decoder.unbox(self.element, as: UInt64.self)
        }

        func decode<T>(_: T.Type) throws -> T where T: Decodable {
            try self.decoder.unbox(self.element, as: T.self)
        }
    }

    func unbox(_ element: XML.Node, as type: Bool.Type) throws -> Bool {
        guard let value = element.stringValue, let unboxValue = Bool(value) else {
            throw DecodingError._typeMismatch(at: self.codingPath, expectation: Bool.self, reality: element.stringValue ?? "nil")
        }
        return unboxValue
    }

    func unbox(_ element: XML.Node, as type: String.Type) throws -> String {
        guard let unboxValue = element.stringValue else {
            throw DecodingError._typeMismatch(at: self.codingPath, expectation: String.self, reality: element.stringValue ?? "nil")
        }
        return unboxValue
    }

    func unbox(_ element: XML.Node, as type: Int.Type) throws -> Int {
        guard let value = element.stringValue, let unboxValue = Int(value) else {
            throw DecodingError._typeMismatch(at: self.codingPath, expectation: Int.self, reality: element.stringValue ?? "nil")
        }
        return unboxValue
    }

    func unbox(_ element: XML.Node, as type: Int8.Type) throws -> Int8 {
        guard let value = element.stringValue, let unboxValue = Int8(value) else {
            throw DecodingError._typeMismatch(at: self.codingPath, expectation: Int8.self, reality: element.stringValue ?? "nil")
        }
        return unboxValue
    }

    func unbox(_ element: XML.Node, as type: Int16.Type) throws -> Int16 {
        guard let value = element.stringValue, let unboxValue = Int16(value) else {
            throw DecodingError._typeMismatch(at: self.codingPath, expectation: Int16.self, reality: element.stringValue ?? "nil")
        }
        return unboxValue
    }

    func unbox(_ element: XML.Node, as type: Int32.Type) throws -> Int32 {
        guard let value = element.stringValue, let unboxValue = Int32(value) else {
            throw DecodingError._typeMismatch(at: self.codingPath, expectation: Int32.self, reality: element.stringValue ?? "nil")
        }
        return unboxValue
    }

    func unbox(_ element: XML.Node, as type: Int64.Type) throws -> Int64 {
        guard let value = element.stringValue, let unboxValue = Int64(value) else {
            throw DecodingError._typeMismatch(at: self.codingPath, expectation: Int64.self, reality: element.stringValue ?? "nil")
        }
        return unboxValue
    }

    func unbox(_ element: XML.Node, as type: UInt.Type) throws -> UInt {
        guard let value = element.stringValue, let unboxValue = UInt(value) else {
            throw DecodingError._typeMismatch(at: self.codingPath, expectation: UInt.self, reality: element.stringValue ?? "nil")
        }
        return unboxValue
    }

    func unbox(_ element: XML.Node, as type: UInt8.Type) throws -> UInt8 {
        guard let value = element.stringValue, let unboxValue = UInt8(value) else {
            throw DecodingError._typeMismatch(at: self.codingPath, expectation: UInt8.self, reality: element.stringValue ?? "nil")
        }
        return unboxValue
    }

    func unbox(_ element: XML.Node, as type: UInt16.Type) throws -> UInt16 {
        guard let value = element.stringValue, let unboxValue = UInt16(value) else {
            throw DecodingError._typeMismatch(at: self.codingPath, expectation: UInt16.self, reality: element.stringValue ?? "nil")
        }
        return unboxValue
    }

    func unbox(_ element: XML.Node, as type: UInt32.Type) throws -> UInt32 {
        guard let value = element.stringValue, let unboxValue = UInt32(value) else {
            throw DecodingError._typeMismatch(at: self.codingPath, expectation: UInt32.self, reality: element.stringValue ?? "nil")
        }
        return unboxValue
    }

    func unbox(_ element: XML.Node, as type: UInt64.Type) throws -> UInt64 {
        guard let value = element.stringValue, let unboxValue = UInt64(value) else {
            throw DecodingError._typeMismatch(at: self.codingPath, expectation: UInt64.self, reality: element.stringValue ?? "nil")
        }
        return unboxValue
    }

    func unbox(_ element: XML.Node, as type: Double.Type) throws -> Double {
        guard let value = element.stringValue, let unboxValue = Double(value) else {
            throw DecodingError._typeMismatch(at: self.codingPath, expectation: Double.self, reality: element.stringValue ?? "nil")
        }
        return unboxValue
    }

    func unbox(_ element: XML.Node, as type: Float.Type) throws -> Float {
        guard let value = element.stringValue, let unboxValue = Float(value) else {
            throw DecodingError._typeMismatch(at: self.codingPath, expectation: Float.self, reality: element.stringValue ?? "nil")
        }
        return unboxValue
    }

    fileprivate func unbox(_ element: XML.Node?, as type: Date.Type) throws -> Date {
        guard let element else {
            throw DecodingError.keyNotFound(
                self.codingPath.last!,
                DecodingError.Context(codingPath: self.codingPath, debugDescription: "Key not found")
            )
        }

        let string = try self.unbox(element, as: String.self)
        for formatter in Self.dateFormatters {
            if let date = formatter.date(from: string) {
                return date
            }
        }
        throw DecodingError.dataCorrupted(
            DecodingError.Context(codingPath: self.codingPath, debugDescription: "Date string does not match format expected")
        )
    }

    /// get Data from XML.Node
    fileprivate func unbox(_ element: XML.Node?, as type: Data.Type) throws -> Data {
        guard let element else {
            throw DecodingError.keyNotFound(
                self.codingPath.last!,
                DecodingError.Context(codingPath: self.codingPath, debugDescription: "Key not found")
            )
        }
        switch self.options.dataDecodingStrategy {
        case .base64:
            guard let string = element.stringValue else {
                throw DecodingError._typeMismatch(at: self.codingPath, expectation: type, reality: element.stringValue ?? "nil")
            }

            guard let data = Data(base64Encoded: string) else {
                throw DecodingError.dataCorrupted(
                    DecodingError.Context(codingPath: self.codingPath, debugDescription: "Encountered Data is not valid Base64.")
                )
            }

            return data

        case .custom(let closure):
            self.storage.push(container: element)
            defer { self.storage.popContainer() }
            return try closure(self)
        }
    }

    func unbox<T>(_ element: XML.Node?, as type: T.Type) throws -> T where T: Decodable {
        try self.unbox_(element, as: T.self) as! T
    }

    func unbox_(_ element: XML.Node?, as type: Decodable.Type) throws -> Any {
        if type == Data.self {
            return try self.unbox(element, as: Data.self)
        } else if type == Date.self {
            return try self.unbox(element, as: Date.self)
        } else {
            self.storage.push(container: element)
            defer { self.storage.popContainer() }
            return try type.init(from: self)
        }
    }

    #if compiler(>=5.10)
    nonisolated(unsafe) static let dateFormatters: [ISO8601DateFormatter] = {
        let dateFormatters: [ISO8601DateFormatter] = [ISO8601DateFormatter(), ISO8601DateFormatter()]
        dateFormatters[0].formatOptions = [.withFullDate, .withFullTime, .withFractionalSeconds]
        dateFormatters[1].formatOptions = [.withFullDate, .withFullTime]
        return dateFormatters
    }()
    #else
    static let dateFormatters: [ISO8601DateFormatter] = {
        let dateFormatters: [ISO8601DateFormatter] = [ISO8601DateFormatter(), ISO8601DateFormatter()]
        dateFormatters[0].formatOptions = [.withFullDate, .withFullTime, .withFractionalSeconds]
        dateFormatters[1].formatOptions = [.withFullDate, .withFullTime]
        return dateFormatters
    }()
    #endif
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

        let debugDescription =
            "Unable to encode \(valueDescription) directly. Use DictionaryEncoder.NonConformingFloatEncodingStrategy.convertToString to specify how the value should be encoded."
        return .invalidValue(value, EncodingError.Context(codingPath: codingPath, debugDescription: debugDescription))
    }
}

extension DecodingError {
    /// Returns a `.typeMismatch` error describing the expected type.
    ///
    /// - parameter path: The path of `CodingKey`s taken to decode a value of this type.
    /// - parameter expectation: The type expected to be encountered.
    /// - parameter reality: The value that was encountered instead of the expected type.
    /// - returns: A `DecodingError` with the appropriate path and debug description.
    static func _typeMismatch(at path: [CodingKey], expectation: Any.Type, reality: Any) -> DecodingError {
        let description = "Expected to decode \(expectation) but found \(_typeDescription(of: reality)) instead."
        return .typeMismatch(expectation, Context(codingPath: path, debugDescription: description))
    }

    /// Returns a description of the type of `value` appropriate for an error message.
    ///
    /// - parameter value: The value whose type to describe.
    /// - returns: A string describing `value`.
    /// - precondition: `value` is one of the types below.
    fileprivate static func _typeDescription(of value: Any) -> String {
        if value is NSNull {
            return "a null value"
        } else if value
            is NSNumber /* FIXME: If swift-corelibs-foundation isn't updated to use NSNumber, this check will be necessary: || value is Int || value is Double */
        {
            return "a number"
        } else if value is String {
            return "a string/data"
        } else if value is [Any] {
            return "an array"
        } else if value is [String: Any] {
            return "a dictionary"
        } else {
            return "\(type(of: value))"
        }
    }
}
