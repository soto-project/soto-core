// EncoderProperties.swift
// Encoder Property Wrappers that control how arrays and dictionaries are output
// Written by Adam Fowler 2020/03/16
//

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

public protocol Coder {
    associatedtype CodableValue: Codable
    
    static func encode(value: CodableValue, to encoder: Encoder) throws
    static func decode(from decoder: Decoder) throws -> CodableValue
}

@propertyWrapper public struct Coding<CustomCoder: Coder>: Codable {
    var value: CustomCoder.CodableValue

    public init(wrappedValue value: CustomCoder.CodableValue) {
        self.value = value
    }

    public init(from decoder: Decoder) throws {
        self.value = try CustomCoder.decode(from: decoder)
    }

    public func encode(to encoder: Encoder) throws {
        try CustomCoder.encode(value: value, to: encoder)
    }
    
    public var wrappedValue: CustomCoder.CodableValue {
        get { return self.value }
    }
}

@propertyWrapper public struct OptionalCoding<CustomCoder: Coder>: Codable {
    var value: CustomCoder.CodableValue?

    public init(wrappedValue value: CustomCoder.CodableValue?) {
        self.value = value
    }

    public init(from decoder: Decoder) throws {
        self.value = try CustomCoder.decode(from: decoder)
    }

    public func encode(to encoder: Encoder) throws {
        guard let value = self.value else { return }
        try CustomCoder.encode(value: value, to: encoder)
    }
    
    public var wrappedValue: CustomCoder.CodableValue? {
        get { return self.value }
    }
}

/// Protocol for a PropertyWrapper to properly handle Coding when the wrappedValue is Optional
public protocol OptionalCodingWrapper {
    associatedtype WrappedType
    var wrappedValue: WrappedType? { get }
    init(wrappedValue: WrappedType?)
}


extension KeyedDecodingContainer {
    // This is used to override the default decoding behavior for OptionalCodingWrapper to allow a value to avoid a missing key Error
    public func decode<T>(_ type: T.Type, forKey key: KeyedDecodingContainer<K>.Key) throws -> T where T : Decodable, T: OptionalCodingWrapper {
        return try decodeIfPresent(T.self, forKey: key) ?? T(wrappedValue: nil)
    }
}

extension KeyedEncodingContainer {
    // Used to make make sure OptionalCodingWrappers encode no value when it's wrappedValue is nil.
    public mutating func encode<T>(_ value: T, forKey key: KeyedEncodingContainer<K>.Key) throws where T: Encodable, T: OptionalCodingWrapper {
        guard value.wrappedValue != nil else {return}
        try encodeIfPresent(value, forKey: key)
    }
}

extension OptionalCoding: OptionalCodingWrapper {}

/// Protocol for array encoding properties. The only property required is the array element name `member`
public protocol ArrayCoderProperties {
    static var member: String { get }
}

/// The most common array encoding property is an element name "member"
public struct ArrayMember: ArrayCoderProperties {
    public static let member = "member"
}

public struct ArrayCoder<Properties: ArrayCoderProperties, Element: Codable>: Coder {
    public typealias CodableValue = [Element]
    public static func decode(from decoder: Decoder) throws -> CodableValue {
        let topLevelContainter = try decoder.container(keyedBy: _EncodingWrapperKey.self)
        var container = try topLevelContainter.nestedUnkeyedContainer(forKey: _EncodingWrapperKey(stringValue: Properties.member, intValue: nil))
        var values: [Element] = []
        while !container.isAtEnd {
            values.append(try container.decode(Element.self))
        }
        return values
    }

    public static func encode(value: CodableValue, to encoder: Encoder) throws {
        var topLevelContainter = encoder.container(keyedBy: _EncodingWrapperKey.self)
        var container = topLevelContainter.nestedUnkeyedContainer(forKey: _EncodingWrapperKey(stringValue: Properties.member, intValue: nil))
        for entry in value {
            try container.encode(entry)
        }
    }
}

/// Protocol for dictionary encoding properties. The property required are the dictionary element name `entry`, the key name `key` and the value name `value`
public protocol DictionaryCoderProperties {
    static var entry: String? { get }
    static var key: String { get }
    static var value: String { get }
}

/// The most common dictionary encoding properties are element name "entry", key name "key", value name "value"
public struct DictionaryEntryKeyValue: DictionaryCoderProperties {
    public static let entry: String? = "entry"
    public static let key = "key"
    public static let value = "value"
}

public struct DictionaryCoder<Properties: DictionaryCoderProperties, Key: Codable & Hashable, Value: Codable>: Coder {
    public typealias CodableValue = [Key: Value]

    public static func decode(from decoder: Decoder) throws -> CodableValue {
        var values: [Key: Value] = [:]
        if let entry = Properties.entry {
            let topLevelContainer = try decoder.container(keyedBy: _EncodingWrapperKey.self)
            var container = try topLevelContainer.nestedUnkeyedContainer(forKey: _EncodingWrapperKey(stringValue: entry, intValue: nil))
            while !container.isAtEnd {
                let container2 = try container.nestedContainer(keyedBy: _EncodingWrapperKey.self)
                let key = try container2.decode(Key.self, forKey: _EncodingWrapperKey(stringValue: Properties.key, intValue: nil))
                let value = try container2.decode(Value.self, forKey: _EncodingWrapperKey(stringValue: Properties.value, intValue: nil))
                values[key] = value
            }
        } else {
            var container = try decoder.unkeyedContainer()
            while !container.isAtEnd {
                let container2 = try container.nestedContainer(keyedBy: _EncodingWrapperKey.self)
                let key = try container2.decode(Key.self, forKey: _EncodingWrapperKey(stringValue: Properties.key, intValue: nil))
                let value = try container2.decode(Value.self, forKey: _EncodingWrapperKey(stringValue: Properties.value, intValue: nil))
                values[key] = value
            }
        }
        return values
    }

    public static func encode(value: CodableValue, to encoder: Encoder) throws {
        if let entry = Properties.entry {
            var topLevelContainter = encoder.container(keyedBy: _EncodingWrapperKey.self)
            var container = topLevelContainter.nestedUnkeyedContainer(forKey: _EncodingWrapperKey(stringValue: entry, intValue: nil))
            for (key, value) in value {
                var container2 = container.nestedContainer(keyedBy: _EncodingWrapperKey.self)
                try container2.encode(key, forKey: _EncodingWrapperKey(stringValue: Properties.key, intValue: nil))
                try container2.encode(value, forKey: _EncodingWrapperKey(stringValue: Properties.value, intValue: nil))
            }
        } else {
            var container = encoder.unkeyedContainer()
            for (key, value) in value {
                var container2 = container.nestedContainer(keyedBy: _EncodingWrapperKey.self)
                try container2.encode(key, forKey: _EncodingWrapperKey(stringValue: Properties.key, intValue: nil))
                try container2.encode(value, forKey: _EncodingWrapperKey(stringValue: Properties.value, intValue: nil))
            }
        }
    }
}
