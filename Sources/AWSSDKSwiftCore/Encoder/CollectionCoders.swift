// CollectionCoders.swift
// Coders to be used with @Coding for outputting arrays and dictionaries
// Written by Adam Fowler 2020/03/18
//

// ArrayCoder

/// Protocol for array encoding properties. The only property required is the array element name `member`
public protocol ArrayCoderProperties {
    static var member: String { get }
}

public struct ArrayCoder<Properties: ArrayCoderProperties, Element: Codable>: CustomCoder {
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

// DictionaryCoder

/// Protocol for dictionary encoding properties. The property required are the dictionary element name `entry`, the key name `key` and the value name `value`
public protocol DictionaryCoderProperties {
    static var entry: String? { get }
    static var key: String { get }
    static var value: String { get }
}

public struct DictionaryCoder<Properties: DictionaryCoderProperties, Key: Codable & Hashable, Value: Codable>: CustomCoder {
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

//MARK: Default Collection Coders

/// The most common array encoding property is an element name "member"
public struct DefaultArrayCoderProperties: ArrayCoderProperties {
    public static let member = "member"
}

/// The most common dictionary encoding properties are element name "entry", key name "key", value name "value"
public struct DefaultDictionaryCoderProperties: DictionaryCoderProperties {
    public static let entry: String? = "entry"
    public static let key = "key"
    public static let value = "value"
}

public typealias DefaultArrayCoder<Element: Codable> = ArrayCoder<DefaultArrayCoderProperties, Element>
public typealias DefaultDictionaryCoder<Key: Codable & Hashable, Value: Codable> = DictionaryCoder<DefaultDictionaryCoderProperties, Key, Value>
