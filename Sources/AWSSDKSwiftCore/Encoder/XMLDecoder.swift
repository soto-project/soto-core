import Foundation

public class AWSXMLDecoder {
    public init() {}

    public func decode<T : Decodable>(_ type: T.Type, from xml: XMLElement) throws -> T {
        let decoder = _AWSXMLDecoder(xml)
        let value = try T(from: decoder)
        return value
    }
}

extension XMLElement {
    func child(for key: CodingKey) -> XMLElement? {
        return (children ?? []).first(where: {$0.name == key.stringValue}) as? XMLElement
    }
}

class _AWSXMLDecoder : Decoder {
    public var codingPath: [CodingKey] = []
    public var userInfo: [CodingUserInfoKey : Any] = [:]
    let elements : [XMLElement]

    public init(_ element : XMLElement) {
        self.elements = [element]
    }

    init(elements : [XMLElement]) {
        self.elements = elements
    }

    public func container<Key>(keyedBy type: Key.Type) throws -> KeyedDecodingContainer<Key> where Key : CodingKey {
        return KeyedDecodingContainer(KDC(elements[0]))
    }

    struct KDC<Key: CodingKey> : KeyedDecodingContainerProtocol {
        var codingPath: [CodingKey] = []
        var allKeys: [Key] = []
        var allValueElements: [String : XMLElement] = [:]
        let element : XMLElement
        let expandedDictionary : Bool // are we decoding a dictionary of the form <entry><key></key><value></value></entry><entry>...

        public init(_ element : XMLElement) {
            self.element = element
            // is element a dictionary in the form <entry><key></key><value></value></entry><entry>...
            if (element.children?.allSatisfy {$0.name == "entry"}) == true {
                if let entries = element.children?.compactMap( { $0 as? XMLElement } ) {
                    for entry in entries {
                        if let keyElement = entry.elements(forName:"key").first, let valueElement = entry.elements(forName:"value").first {
                            let keyString = keyElement.stringValue!
                            if let key = Key(stringValue: keyString) {
                                allKeys.append(key)
                                // store value elements for later
                                allValueElements[keyString] = valueElement
                            }
                        }
                    }
                }
                expandedDictionary = true
            } else {
                allKeys = element.children?.compactMap { (element: Foundation.XMLNode)->Key? in
                    if let name = element.name {
                        return Key(stringValue: name)
                    }
                    return nil
                } ?? []
                expandedDictionary = false
            }
        }

        func contains(_ key: Key) -> Bool {
            return element.child(for: key) != nil
        }

        func child(for key: CodingKey) throws -> XMLElement {
            if expandedDictionary {
                guard let child = allValueElements[key.stringValue] else {
                    throw DecodingError.keyNotFound(key, DecodingError.Context(codingPath: codingPath, debugDescription:"Failed to find key value in expanded dictionary. Should not get here"))
                }
                return child
            } else {
                guard let child = element.child(for: key) else {
                    throw DecodingError.keyNotFound(key, DecodingError.Context(codingPath: codingPath, debugDescription: "Key not found"))
                }
                return child
            }
        }

        func children(for key: CodingKey) throws -> [XMLElement] {
            if expandedDictionary {
                guard let child = allValueElements[key.stringValue] else {
                    throw DecodingError.keyNotFound(key, DecodingError.Context(codingPath: codingPath, debugDescription:"Failed to find key value in expanded dictionary. Should not get here"))
                }
                return [child]
            } else {
                guard let children = element.children?.compactMap({$0.name == key.stringValue ? ($0 as? XMLElement) : nil}) else {
                    throw DecodingError.keyNotFound(key, DecodingError.Context(codingPath: codingPath, debugDescription: "Key not found"))
                }
                return children
            }
        }

        func decodeNil(forKey key: Key) throws -> Bool {
            let child = try self.child(for: key)
            return child.attribute(forName: "nil") != nil
        }

        func decode(_ type: Bool.Type, forKey key: Key) throws -> Bool {
            let child = try self.child(for: key)
            guard let value = Bool(child.stringValue!) else { throw DecodingError.dataCorrupted(DecodingError.Context(codingPath: codingPath, debugDescription: "Cannot convert to boolean"))}
            return value
        }

        func decode(_ type: String.Type, forKey key: Key) throws -> String {
            return try child(for: key).stringValue!
        }

        func decode(_ type: Double.Type, forKey key: Key) throws -> Double {
            let child = try self.child(for: key)
            guard let value = Double(child.stringValue!) else { throw DecodingError.dataCorrupted(DecodingError.Context(codingPath: codingPath, debugDescription: "Cannot convert to double"))}
            return value
        }

        func decode(_ type: Float.Type, forKey key: Key) throws -> Float {
            let child = try self.child(for: key)
            guard let value = Float(child.stringValue!) else { throw DecodingError.dataCorrupted(DecodingError.Context(codingPath: codingPath, debugDescription: "Cannot convert to float"))}
            return value
        }

        func decode(_ type: Int.Type, forKey key: Key) throws -> Int {
            let child = try self.child(for: key)
            guard let value = Int(child.stringValue!) else { throw DecodingError.dataCorrupted(DecodingError.Context(codingPath: codingPath, debugDescription: "Cannot convert to integer"))}
            return value
        }

        func decode(_ type: Int8.Type, forKey key: Key) throws -> Int8 {
            fatalError()
        }

        func decode(_ type: Int16.Type, forKey key: Key) throws -> Int16 {
            fatalError()
        }

        func decode(_ type: Int32.Type, forKey key: Key) throws -> Int32 {
            fatalError()
        }

        func decode(_ type: Int64.Type, forKey key: Key) throws -> Int64 {
            fatalError()
        }

        func decode(_ type: UInt.Type, forKey key: Key) throws -> UInt {
            fatalError()
        }

        func decode(_ type: UInt8.Type, forKey key: Key) throws -> UInt8 {
            fatalError()
        }

        func decode(_ type: UInt16.Type, forKey key: Key) throws -> UInt16 {
            fatalError()
        }

        func decode(_ type: UInt32.Type, forKey key: Key) throws -> UInt32 {
            fatalError()
        }

        func decode(_ type: UInt64.Type, forKey key: Key) throws -> UInt64 {
            fatalError()
        }

        func decode<Key, Value>(_ type: Dictionary<Key, Value>.Type, forKey key: Key) throws -> UInt64 {
            fatalError()
        }

        func decode<T>(_ type: T.Type, forKey key: Key) throws -> T where T : Decodable {
            let elements = try children(for: key)
            let decoder = _AWSXMLDecoder(elements: elements)
            return try T(from: decoder)
        }

        func nestedContainer<NestedKey>(keyedBy type: NestedKey.Type, forKey key: Key) throws -> KeyedDecodingContainer<NestedKey> where NestedKey : CodingKey {
            fatalError()
        }

        func nestedUnkeyedContainer(forKey key: Key) throws -> UnkeyedDecodingContainer {
            fatalError()
        }

        func superDecoder() throws -> Decoder {
            fatalError()
        }

        func superDecoder(forKey key: Key) throws -> Decoder {
            fatalError()
        }

    }

    public func unkeyedContainer() throws -> UnkeyedDecodingContainer {
        return UKDC(elements)
    }

    struct UKDC : UnkeyedDecodingContainer {
        var codingPath: [CodingKey] = []
        var currentIndex: Int = 0
        let elements : [XMLElement]

        init(_ elements: [XMLElement]) {
            // if element count is 1 then count children called member
            if elements.count == 1 && (elements[0].children?.allSatisfy {$0.name == "member"}) == true {
                self.elements = elements[0].children?.compactMap {$0 as? XMLElement} ?? []
            } else {
                self.elements = elements
            }
        }

        var count: Int? {
            return elements.count
        }

        var isAtEnd : Bool {
            return currentIndex >= count!
        }

        mutating func decodeNil() throws -> Bool {
            fatalError()
        }

        mutating func decode(_ type: Bool.Type) throws -> Bool {
            guard let value = Bool(elements[currentIndex].stringValue!) else { throw DecodingError.dataCorrupted(DecodingError.Context(codingPath: codingPath, debugDescription: "Cannot convert to boolean"))}
            currentIndex += 1
            return value
        }

        mutating func decode(_ type: String.Type) throws -> String {
            guard let value = elements[currentIndex].stringValue!
            currentIndex += 1
            return value
        }

        mutating func decode(_ type: Double.Type) throws -> Double {
            fatalError()
        }

        mutating func decode(_ type: Float.Type) throws -> Float {
            fatalError()
        }

        mutating func decode(_ type: Int.Type) throws -> Int {
            fatalError()
        }

        mutating func decode(_ type: Int8.Type) throws -> Int8 {
            fatalError()
        }

        mutating func decode(_ type: Int16.Type) throws -> Int16 {
            fatalError()
        }

        mutating func decode(_ type: Int32.Type) throws -> Int32 {
            fatalError()
        }

        mutating func decode(_ type: Int64.Type) throws -> Int64 {
            fatalError()
        }

        mutating func decode(_ type: UInt.Type) throws -> UInt {
            fatalError()
        }

        mutating func decode(_ type: UInt8.Type) throws -> UInt8 {
            guard let value = UInt8(elements[currentIndex].stringValue!) else { throw DecodingError.dataCorrupted(DecodingError.Context(codingPath: codingPath, debugDescription: "Cannot convert to uint8"))}
            currentIndex += 1
            return value
        }

        mutating func decode(_ type: UInt16.Type) throws -> UInt16 {
            fatalError()
        }

        mutating func decode(_ type: UInt32.Type) throws -> UInt32 {
            fatalError()
        }

        mutating func decode(_ type: UInt64.Type) throws -> UInt64 {
            fatalError()
        }

        mutating func decode<T>(_ type: T.Type) throws -> T where T : Decodable {
            let decoder = _AWSXMLDecoder(elements[currentIndex])
            let decoded = try T(from: decoder)
            currentIndex += 1
            return decoded
        }

        mutating func nestedContainer<NestedKey>(keyedBy type: NestedKey.Type) throws -> KeyedDecodingContainer<NestedKey> where NestedKey : CodingKey {
            fatalError()
        }

        mutating func nestedUnkeyedContainer() throws -> UnkeyedDecodingContainer {
            fatalError()
        }

        mutating func superDecoder() throws -> Decoder {
            fatalError()
        }


    }

    public func singleValueContainer() throws -> SingleValueDecodingContainer {
        return SVDC(elements[0])
    }

    struct SVDC : SingleValueDecodingContainer {
        var codingPath: [CodingKey] = []
        let element : XMLElement

        init(_ element : XMLElement) {
            self.element = element
        }

        func decodeNil() -> Bool {
            fatalError()
        }

        func decode(_ type: Bool.Type) throws -> Bool {
            guard let value = Bool(element.stringValue!) else { throw DecodingError.dataCorrupted(DecodingError.Context(codingPath: codingPath, debugDescription: "Cannot convert to boolean"))}
            return value
        }

        func decode(_ type: String.Type) throws -> String {
            return element.stringValue!
        }

        func decode(_ type: Double.Type) throws -> Double {
            guard let value = Double(element.stringValue!) else { throw DecodingError.dataCorrupted(DecodingError.Context(codingPath: codingPath, debugDescription: "Cannot convert to double"))}
            return value
        }

        func decode(_ type: Float.Type) throws -> Float {
            guard let value = Float(element.stringValue!) else { throw DecodingError.dataCorrupted(DecodingError.Context(codingPath: codingPath, debugDescription: "Cannot convert to float"))}
            return value
        }

        func decode(_ type: Int.Type) throws -> Int {
            guard let value = Int(element.stringValue!) else { throw DecodingError.dataCorrupted(DecodingError.Context(codingPath: codingPath, debugDescription: "Cannot convert to int"))}
            return value
        }

        func decode(_ type: Int8.Type) throws -> Int8 {
            fatalError()
        }

        func decode(_ type: Int16.Type) throws -> Int16 {
            fatalError()
        }

        func decode(_ type: Int32.Type) throws -> Int32 {
            fatalError()
        }

        func decode(_ type: Int64.Type) throws -> Int64 {
            fatalError()
        }

        func decode(_ type: UInt.Type) throws -> UInt {
            fatalError()
        }

        func decode(_ type: UInt8.Type) throws -> UInt8 {
            fatalError()
        }

        func decode(_ type: UInt16.Type) throws -> UInt16 {
            fatalError()
        }

        func decode(_ type: UInt32.Type) throws -> UInt32 {
            fatalError()
        }

        func decode(_ type: UInt64.Type) throws -> UInt64 {
            fatalError()
        }

        func decode<T>(_ type: T.Type) throws -> T where T : Decodable {
            let decoder = _AWSXMLDecoder(element)
            return try T(from: decoder)
        }

    }

}
