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

// MARK: Collection Coders

// ArrayCoder

/// Protocol for array encoding properties. The only property required is the array element name `member`
public protocol ArrayCoderProperties {
    static var member: String { get }
}

/// Coder for encoding/decoding Arrays. This is extended to support encoding and decoding based on whether `Element` is `Encodable` or `Decodable`.
public struct ArrayCoder<Properties: ArrayCoderProperties, Element: _SotoSendable>: CustomCoder {
    public typealias CodableValue = [Element]
}

/// extend to support decoding
extension ArrayCoder: CustomDecoder where Element: Decodable {
    public static func decode(from decoder: Decoder) throws -> CodableValue {
        let topLevelContainer = try decoder.container(keyedBy: EncodingWrapperKey.self)
        var values: [Element] = []
        let memberKey = EncodingWrapperKey(stringValue: Properties.member, intValue: nil)
        guard topLevelContainer.contains(memberKey) else { return values }

        var container = try topLevelContainer.nestedUnkeyedContainer(forKey: memberKey)
        while !container.isAtEnd {
            values.append(try container.decode(Element.self))
        }
        return values
    }
}

/// extend to support encoding
extension ArrayCoder: CustomEncoder where Element: Encodable {
    public static func encode(value: CodableValue, to encoder: Encoder) throws {
        var topLevelContainer = encoder.container(keyedBy: EncodingWrapperKey.self)
        var container = topLevelContainer.nestedUnkeyedContainer(forKey: EncodingWrapperKey(stringValue: Properties.member, intValue: nil))
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

/// Coder for encoding/decoding Dictionaries. This is extended to support encoding and decoding based on whether `Key` and `Value` are `Encodable` or `Decodable`.
public struct DictionaryCoder<Properties: DictionaryCoderProperties, Key: Hashable & _SotoSendable, Value: _SotoSendable>: CustomCoder {
    public typealias CodableValue = [Key: Value]
}

/// extend to support decoding
extension DictionaryCoder: CustomDecoder where Key: Decodable, Value: Decodable {
    public static func decode(from decoder: Decoder) throws -> CodableValue {
        var values: [Key: Value] = [:]
        if let entry = Properties.entry {
            let topLevelContainer = try decoder.container(keyedBy: EncodingWrapperKey.self)
            let entryKey = EncodingWrapperKey(stringValue: entry, intValue: nil)
            guard topLevelContainer.contains(entryKey) else { return values }

            var container = try topLevelContainer.nestedUnkeyedContainer(forKey: entryKey)
            while !container.isAtEnd {
                let container2 = try container.nestedContainer(keyedBy: EncodingWrapperKey.self)
                let key = try container2.decode(Key.self, forKey: EncodingWrapperKey(stringValue: Properties.key, intValue: nil))
                let value = try container2.decode(Value.self, forKey: EncodingWrapperKey(stringValue: Properties.value, intValue: nil))
                values[key] = value
            }
        } else {
            var container = try decoder.unkeyedContainer()
            while !container.isAtEnd {
                let container2 = try container.nestedContainer(keyedBy: EncodingWrapperKey.self)
                let key = try container2.decode(Key.self, forKey: EncodingWrapperKey(stringValue: Properties.key, intValue: nil))
                let value = try container2.decode(Value.self, forKey: EncodingWrapperKey(stringValue: Properties.value, intValue: nil))
                values[key] = value
            }
        }
        return values
    }
}

/// extend to support encoding
extension DictionaryCoder: CustomEncoder where Key: Encodable, Value: Encodable {
    public static func encode(value: CodableValue, to encoder: Encoder) throws {
        if let entry = Properties.entry {
            var topLevelContainter = encoder.container(keyedBy: EncodingWrapperKey.self)
            var container = topLevelContainter.nestedUnkeyedContainer(forKey: EncodingWrapperKey(stringValue: entry, intValue: nil))
            for (key, value) in value {
                var container2 = container.nestedContainer(keyedBy: EncodingWrapperKey.self)
                try container2.encode(key, forKey: EncodingWrapperKey(stringValue: Properties.key, intValue: nil))
                try container2.encode(value, forKey: EncodingWrapperKey(stringValue: Properties.value, intValue: nil))
            }
        } else {
            var container = encoder.unkeyedContainer()
            for (key, value) in value {
                var container2 = container.nestedContainer(keyedBy: EncodingWrapperKey.self)
                try container2.encode(key, forKey: EncodingWrapperKey(stringValue: Properties.key, intValue: nil))
                try container2.encode(value, forKey: EncodingWrapperKey(stringValue: Properties.value, intValue: nil))
            }
        }
    }
}

/// The most common array encoding property is an element name "member"
public struct StandardArrayCoderProperties: ArrayCoderProperties {
    public static let member = "member"
}

/// The most common dictionary encoding properties are element name "entry", key name "key", value name "value"
public struct StandardDictionaryCoderProperties: DictionaryCoderProperties {
    public static let entry: String? = "entry"
    public static let key = "key"
    public static let value = "value"
}

public typealias StandardArrayCoder<Element> = ArrayCoder<StandardArrayCoderProperties, Element>
public typealias StandardDictionaryCoder<Key: Codable & Hashable, Value> = DictionaryCoder<StandardDictionaryCoderProperties, Key, Value>
