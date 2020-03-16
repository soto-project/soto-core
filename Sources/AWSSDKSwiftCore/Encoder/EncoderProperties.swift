
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
    
    fileprivate init(index: Int) {
        self.stringValue = "Index \(index)"
        self.intValue = index
    }
}

/// Array encoding property wrapper
public protocol ArrayEncodingProperties {
    static var member: String { get }
}

extension ArrayEncodingProperties {
    static var memberCodingKey: _EncodingWrapperKey { return  _EncodingWrapperKey(stringValue: member, intValue: nil) }
}
    
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
        set { self.array = newValue }
    }

    private enum CodingKeys: String, CodingKey {
        case member = "member"
    }
}

/// Array encoding property wrapper
public protocol DictionaryEncodingProperties {
    static var entry: String? { get }
    static var key: String { get }
    static var value: String { get }
}

extension DictionaryEncodingProperties {
    static var entryCodingKey: _EncodingWrapperKey? { return  entry.map { _EncodingWrapperKey(stringValue: $0, intValue: nil) } }
    static var keyCodingKey: _EncodingWrapperKey { return  _EncodingWrapperKey(stringValue: key, intValue: nil) }
    static var valueCodingKey: _EncodingWrapperKey { return  _EncodingWrapperKey(stringValue: value, intValue: nil) }
}
    
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
        set { self.dictionary = newValue }
    }
}
