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

/// Protocol for array encoding properties. The only property required is the array element name `member`
public protocol ArrayEncodingProperties {
    static var member: String { get }
}

extension ArrayEncodingProperties {
    /// array element name as CodingKey
    static var memberCodingKey: _EncodingWrapperKey { return  _EncodingWrapperKey(stringValue: member, intValue: nil) }
}

/// The most common array encoding property is an element name "member"
public struct ArrayMember: ArrayEncodingProperties {
    public static let member = "member"
}

/// Array encoding propertyWrapper. Implements Codable functions to include an extra level of container.
@propertyWrapper public struct ArrayEncoding<Properties: ArrayEncodingProperties, Value: Codable>: Codable {
    var array: [Value]

    public init(wrappedValue value: [Value]) {
        self.array = value
    }

    public init(from decoder: Decoder) throws {
        let topLevelContainter = try decoder.container(keyedBy: _EncodingWrapperKey.self)
        var container = try topLevelContainter.nestedUnkeyedContainer(forKey: Properties.memberCodingKey)
        var values: [Value] = []
        while !container.isAtEnd {
            values.append(try container.decode(Value.self))
        }
        self.array = values
    }

    public func encode(to encoder: Encoder) throws {
        var topLevelContainter = encoder.container(keyedBy: _EncodingWrapperKey.self)
        var container = topLevelContainter.nestedUnkeyedContainer(forKey: Properties.memberCodingKey)
        for entry in array {
            try container.encode(entry)
        }
    }

    public var wrappedValue: [Value] {
        get { return self.array }
    }

    private enum CodingKeys: String, CodingKey {
        case member = "member"
    }
}

/// Protocol for dictionary encoding properties. The property required are the dictionary element name `entry`, the key name `key` and the value name `value`
public protocol DictionaryEncodingProperties {
    static var entry: String? { get }
    static var key: String { get }
    static var value: String { get }
}

/// dictionary encoding properties as CodingKeys
extension DictionaryEncodingProperties {
    static var entryCodingKey: _EncodingWrapperKey? { return  entry.map { _EncodingWrapperKey(stringValue: $0, intValue: nil) } }
    static var keyCodingKey: _EncodingWrapperKey { return  _EncodingWrapperKey(stringValue: key, intValue: nil) }
    static var valueCodingKey: _EncodingWrapperKey { return  _EncodingWrapperKey(stringValue: value, intValue: nil) }
}

/// The most common dictionary encoding properties are element name "entry", key name "key", value name "value"
public struct DictionaryEntryKeyValue: DictionaryEncodingProperties {
    public static let entry: String? = "entry"
    public static let key = "key"
    public static let value = "value"
}

/// Dictinoary encoding propertyWrapper. Implements Codable functions to include an extra level of container for each entry (if entry is set), plus containers for each key and each value.
@propertyWrapper public struct DictionaryEncoding<Properties: DictionaryEncodingProperties, Key: Codable & Hashable, Value: Codable>: Codable {
    var dictionary: [Key: Value]

    public init(wrappedValue value: [Key: Value]) {
        self.dictionary = value
    }

    public init(from decoder: Decoder) throws {
        var values: [Key: Value] = [:]
        if let entryCodingKey = Properties.entryCodingKey {
            let topLevelContainer = try decoder.container(keyedBy: _EncodingWrapperKey.self)
            var container = try topLevelContainer.nestedUnkeyedContainer(forKey: entryCodingKey)
            while !container.isAtEnd {
                let container2 = try container.nestedContainer(keyedBy: _EncodingWrapperKey.self)
                let key = try container2.decode(Key.self, forKey: Properties.keyCodingKey)
                let value = try container2.decode(Value.self, forKey: Properties.valueCodingKey)
                values[key] = value
            }
        } else {
            var container = try decoder.unkeyedContainer()
            while !container.isAtEnd {
                let container2 = try container.nestedContainer(keyedBy: _EncodingWrapperKey.self)
                let key = try container2.decode(Key.self, forKey: Properties.keyCodingKey)
                let value = try container2.decode(Value.self, forKey: Properties.valueCodingKey)
                values[key] = value
            }
        }
        self.dictionary = values
    }

    public func encode(to encoder: Encoder) throws {
        if let entryCodingKey = Properties.entryCodingKey {
            var topLevelContainter = encoder.container(keyedBy: _EncodingWrapperKey.self)
            var container = topLevelContainter.nestedUnkeyedContainer(forKey: entryCodingKey)
            for (key, value) in dictionary {
                var container2 = container.nestedContainer(keyedBy: _EncodingWrapperKey.self)
                try container2.encode(key, forKey: Properties.keyCodingKey)
                try container2.encode(value, forKey: Properties.valueCodingKey)
            }
        } else {
            var container = encoder.unkeyedContainer()
            for (key, value) in dictionary {
                var container2 = container.nestedContainer(keyedBy: _EncodingWrapperKey.self)
                try container2.encode(key, forKey: Properties.keyCodingKey)
                try container2.encode(value, forKey: Properties.valueCodingKey)
            }
        }
    }
    
    public var wrappedValue: [Key: Value] {
        get { return self.dictionary }
    }
}
