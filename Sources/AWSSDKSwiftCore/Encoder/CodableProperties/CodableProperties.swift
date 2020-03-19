// EncoderProperties.swift
// Encoder Property Wrappers that apply custom encoding/decoding while using Codable
// Written by Adam Fowler 2020/03/16
//

/// Protocol for object that will encode and decode a value
public protocol CustomCoder {
    associatedtype CodableValue: Codable
    
    static func encode(value: CodableValue, to encoder: Encoder) throws
    static func decode(from decoder: Decoder) throws -> CodableValue
}

/// Property wrapper that applies a custom encoder and decoder to its wrapped value
@propertyWrapper public struct Coding<Coder: CustomCoder>: Codable {
    var value: Coder.CodableValue

    public init(wrappedValue value: Coder.CodableValue) {
        self.value = value
    }

    public init(from decoder: Decoder) throws {
        self.value = try Coder.decode(from: decoder)
    }

    public func encode(to encoder: Encoder) throws {
        try Coder.encode(value: value, to: encoder)
    }
    
    public var wrappedValue: Coder.CodableValue {
        get { return self.value }
        set { self.value = newValue }
    }
}

/// Property wrapper that applies a custom encoder and decoder to its wrapped optional value
@propertyWrapper public struct OptionalCoding<Coder: CustomCoder>: Codable {
    var value: Coder.CodableValue?

    public init(wrappedValue value: Coder.CodableValue?) {
        self.value = value
    }

    public init(from decoder: Decoder) throws {
        self.value = try Coder.decode(from: decoder)
    }

    public func encode(to encoder: Encoder) throws {
        guard let value = self.value else { return }
        try Coder.encode(value: value, to: encoder)
    }
    
    public var wrappedValue: Coder.CodableValue? {
        get { return self.value }
        set { self.value = newValue }
    }
}

/// Protocol for a PropertyWrapper to properly handle Coding when the wrappedValue is Optional
public protocol OptionalCodingWrapper {
    associatedtype WrappedType
    var wrappedValue: WrappedType? { get }
    init(wrappedValue: WrappedType?)
}

/// extending `KeyedDecodingContainer` so it will only decode an optional value if it is present
extension KeyedDecodingContainer {
    // This is used to override the default decoding behavior for OptionalCodingWrapper to allow a value to avoid a missing key Error
    public func decode<T>(_ type: T.Type, forKey key: KeyedDecodingContainer<K>.Key) throws -> T where T : Decodable, T: OptionalCodingWrapper {
        return try decodeIfPresent(T.self, forKey: key) ?? T(wrappedValue: nil)
    }
}

/// extending `KeyedEncodingContainer` so it will only encode a wrapped value it is non nil
extension KeyedEncodingContainer {
    // Used to make make sure OptionalCodingWrappers encode no value when it's wrappedValue is nil.
    public mutating func encode<T>(_ value: T, forKey key: KeyedEncodingContainer<K>.Key) throws where T: Encodable, T: OptionalCodingWrapper {
        guard value.wrappedValue != nil else {return}
        try encodeIfPresent(value, forKey: key)
    }
}

/// extend OptionalCoding so it conforms to OptionalCodingWrapper
extension OptionalCoding: OptionalCodingWrapper {}

/// CodingKey used by Encoder property wrappers
internal struct _EncodingWrapperKey : CodingKey {
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

