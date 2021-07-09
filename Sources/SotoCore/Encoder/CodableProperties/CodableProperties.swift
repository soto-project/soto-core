//===----------------------------------------------------------------------===//
//
// This source file is part of the Soto for AWS open source project
//
// Copyright (c) 2020 the Soto project authors
// Licensed under Apache License v2.0
//
// See LICENSE.txt for license information
// See CONTRIBUTORS.txt for the list of Soto project authors
//
// SPDX-License-Identifier: Apache-2.0
//
//===----------------------------------------------------------------------===//

// This code takes inspiration from https://github.com/GottaGetSwifty/CodableWrappers
import JMESPath

/// base protocol for encoder/decoder objects
public protocol CustomCoder {
    associatedtype CodableValue
}

/// Protocol for object that will encode a value
public protocol CustomEncoder: CustomCoder {
    /// encode CodableValue with supplied encoder
    static func encode(value: CodableValue, to encoder: Encoder) throws
    /// return value as a String. Used by query string and header values
    static func string(from: CodableValue) -> String?
}

extension CustomEncoder {
    public static func string(from: CodableValue) -> String? { return nil }
}

/// Protocol for object that will decode a value
public protocol CustomDecoder: CustomCoder {
    static func decode(from decoder: Decoder) throws -> CodableValue
}

/// Property wrapper that applies a custom encoder and decoder to its wrapped value
@propertyWrapper public struct CustomCoding<Coder: CustomCoder> {
    var value: Coder.CodableValue

    public init(wrappedValue value: Coder.CodableValue) {
        self.value = value
    }

    public var wrappedValue: Coder.CodableValue {
        get { return self.value }
        set { self.value = newValue }
    }
}

/// add decode functionality if propertyWrapper conforms to `Decodable` and Coder conforms to `CustomDecoder`
extension CustomCoding: Decodable where Coder: CustomDecoder {
    public init(from decoder: Decoder) throws {
        self.value = try Coder.decode(from: decoder)
    }
}

/// add encoder functionality if propertyWrapper conforms to `Encodable` and Coder conforms to `CustomEncoder`
extension CustomCoding: Encodable where Coder: CustomEncoder {
    public func encode(to encoder: Encoder) throws {
        try Coder.encode(value: self.value, to: encoder)
    }
}

/// extend CustomCoding property wrapper so JMESPath works correctly with it
extension CustomCoding: JMESPropertyWrapper {
    public var anyValue: Any {
        return self.value
    }
}

/// Property wrapper that applies a custom encoder and decoder to its wrapped optional value
@propertyWrapper public struct OptionalCustomCoding<Coder: CustomCoder> {
    var value: Coder.CodableValue?

    public init(wrappedValue value: Coder.CodableValue?) {
        self.value = value
    }

    public var wrappedValue: Coder.CodableValue? {
        get { return self.value }
        set { self.value = newValue }
    }
}

/// add decode functionality if propertyWrapper conforms to `Decodable` and Coder conforms to `CustomDecoder`
extension OptionalCustomCoding: Decodable where Coder: CustomDecoder {
    public init(from decoder: Decoder) throws {
        self.value = try Coder.decode(from: decoder)
    }
}

/// add encoder functionality if propertyWrapper conforms to `Encodable` and Coder conforms to `CustomEncoder`
extension OptionalCustomCoding: Encodable where Coder: CustomEncoder {
    public func encode(to encoder: Encoder) throws {
        guard let value = self.value else { return }
        try Coder.encode(value: value, to: encoder)
    }
}

/// extend OptionalCustomCoding property wrapper so JMESPath works correctly with it
extension OptionalCustomCoding: JMESPropertyWrapper {
    public var anyValue: Any {
        return self.value as Any
    }
}
/// Protocol for a PropertyWrapper to properly handle CustomCoding when the wrappedValue is Optional
public protocol OptionalCustomCodingWrapper {
    associatedtype WrappedType
    var wrappedValue: WrappedType? { get }
    init(wrappedValue: WrappedType?)
}

/// extending `KeyedDecodingContainer` so it will only decode an optional value if it is present
extension KeyedDecodingContainer {
    // This is used to override the default decoding behavior for OptionalCodingWrapper to allow a value to avoid a missing key Error
    public func decode<T>(_ type: T.Type, forKey key: KeyedDecodingContainer<K>.Key) throws -> T where T: Decodable, T: OptionalCustomCodingWrapper {
        return try decodeIfPresent(T.self, forKey: key) ?? T(wrappedValue: nil)
    }
}

/// extending `KeyedEncodingContainer` so it will only encode a wrapped value it is non nil
extension KeyedEncodingContainer {
    // Used to make make sure OptionalCodingWrappers encode no value when it's wrappedValue is nil.
    public mutating func encode<T>(_ value: T, forKey key: KeyedEncodingContainer<K>.Key) throws where T: Encodable, T: OptionalCustomCodingWrapper {
        guard value.wrappedValue != nil else { return }
        try encodeIfPresent(value, forKey: key)
    }
}

/// extend OptionalCoding so it conforms to OptionalCodingWrapper
extension OptionalCustomCoding: OptionalCustomCodingWrapper {}

/// CodingKey used by Encoder property wrappers
internal struct EncodingWrapperKey: CodingKey {
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
}
