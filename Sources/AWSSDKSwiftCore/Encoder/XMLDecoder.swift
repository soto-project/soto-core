//
//  XMLEncoder.swift
//  AWSSDKSwift
//
//  Created by Adam Fowler on 2019/05/01.
//
//
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
    public var codingPath: [CodingKey]
    public var userInfo: [CodingUserInfoKey : Any] = [:]
    let elements : [XMLElement]

    public init(_ element : XMLElement, at codingPath: [CodingKey] = []) {
        self.elements = [element]
        self.codingPath = codingPath
    }

    init(elements : [XMLElement], at codingPath: [CodingKey] ) {
        self.elements = elements
        self.codingPath = codingPath
    }

    public func container<Key>(keyedBy type: Key.Type) throws -> KeyedDecodingContainer<Key> where Key : CodingKey {
        return KeyedDecodingContainer(KDC(elements[0], decoder: self))
    }

    struct KDC<Key: CodingKey> : KeyedDecodingContainerProtocol {
        var codingPath: [CodingKey] { return decoder.codingPath }
        var allKeys: [Key] = []
        var allValueElements: [String : XMLElement] = [:]
        let element : XMLElement
        let decoder : _AWSXMLDecoder
        let expandedDictionary : Bool // are we decoding a dictionary of the form <entry><key></key><value></value></entry><entry>...

        public init(_ element : XMLElement, decoder: _AWSXMLDecoder) {
            self.element = element
            self.decoder = decoder
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
                guard children.count > 0 else {
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
            return try decoder.unbox(child.stringValue, as:Bool.self)
        }

        func decode(_ type: String.Type, forKey key: Key) throws -> String {
            let child = try self.child(for: key)
            return try decoder.unbox(child.stringValue, as:String.self)
        }

        func decode(_ type: Double.Type, forKey key: Key) throws -> Double {
            let child = try self.child(for: key)
            return try decoder.unbox(child.stringValue, as:Double.self)
        }

        func decode(_ type: Float.Type, forKey key: Key) throws -> Float {
            let child = try self.child(for: key)
            return try decoder.unbox(child.stringValue, as:Float.self)
        }

        func decode(_ type: Int.Type, forKey key: Key) throws -> Int {
            let child = try self.child(for: key)
            return try decoder.unbox(child.stringValue, as:Int.self)
        }

        func decode(_ type: Int8.Type, forKey key: Key) throws -> Int8 {
            let child = try self.child(for: key)
            return try decoder.unbox(child.stringValue, as:Int8.self)
        }

        func decode(_ type: Int16.Type, forKey key: Key) throws -> Int16 {
            let child = try self.child(for: key)
            return try decoder.unbox(child.stringValue, as:Int16.self)
        }

        func decode(_ type: Int32.Type, forKey key: Key) throws -> Int32 {
            let child = try self.child(for: key)
            return try decoder.unbox(child.stringValue, as:Int32.self)
        }

        func decode(_ type: Int64.Type, forKey key: Key) throws -> Int64 {
            let child = try self.child(for: key)
            return try decoder.unbox(child.stringValue, as:Int64.self)
        }

        func decode(_ type: UInt.Type, forKey key: Key) throws -> UInt {
            let child = try self.child(for: key)
            return try decoder.unbox(child.stringValue, as:UInt.self)
        }

        func decode(_ type: UInt8.Type, forKey key: Key) throws -> UInt8 {
            let child = try self.child(for: key)
            return try decoder.unbox(child.stringValue, as:UInt8.self)
        }

        func decode(_ type: UInt16.Type, forKey key: Key) throws -> UInt16 {
            let child = try self.child(for: key)
            return try decoder.unbox(child.stringValue, as:UInt16.self)
        }

        func decode(_ type: UInt32.Type, forKey key: Key) throws -> UInt32 {
            let child = try self.child(for: key)
            return try decoder.unbox(child.stringValue, as:UInt32.self)
        }

        func decode(_ type: UInt64.Type, forKey key: Key) throws -> UInt64 {
            let child = try self.child(for: key)
            return try decoder.unbox(child.stringValue, as:UInt64.self)
        }

        func decode<T>(_ type: T.Type, forKey key: Key) throws -> T where T : Decodable {
            self.decoder.codingPath.append(key)
            defer { self.decoder.codingPath.removeLast() }

            let elements = try children(for: key)
            let decoder = _AWSXMLDecoder(elements: elements, at:codingPath)
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
        return UKDC(elements, decoder: self)
    }

    struct UKDC : UnkeyedDecodingContainer {
        var codingPath: [CodingKey] { return decoder.codingPath }
        var currentIndex: Int = 0
        let elements : [XMLElement]
        let decoder : _AWSXMLDecoder

        init(_ elements: [XMLElement], decoder: _AWSXMLDecoder) {
            // if element count is 1 then count children called member
            if elements.count == 1 && (elements[0].children?.allSatisfy {$0.name == "member"}) == true {
                self.elements = elements[0].children?.compactMap {$0 as? XMLElement} ?? []
            } else {
                self.elements = elements
            }
            self.decoder = decoder
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
            let value = try decoder.unbox(elements[currentIndex].stringValue, as: Bool.self)
            currentIndex += 1
            return value
        }

        mutating func decode(_ type: String.Type) throws -> String {
            let value = try decoder.unbox(elements[currentIndex].stringValue, as: String.self)
            currentIndex += 1
            return value
        }

        mutating func decode(_ type: Double.Type) throws -> Double {
            let value = try decoder.unbox(elements[currentIndex].stringValue, as: Double.self)
            currentIndex += 1
            return value
        }

        mutating func decode(_ type: Float.Type) throws -> Float {
            let value = try decoder.unbox(elements[currentIndex].stringValue, as: Float.self)
            currentIndex += 1
            return value
        }

        mutating func decode(_ type: Int.Type) throws -> Int {
            let value = try decoder.unbox(elements[currentIndex].stringValue, as: Int.self)
            currentIndex += 1
            return value
        }

        mutating func decode(_ type: Int8.Type) throws -> Int8 {
            let value = try decoder.unbox(elements[currentIndex].stringValue, as: Int8.self)
            currentIndex += 1
            return value
        }

        mutating func decode(_ type: Int16.Type) throws -> Int16 {
            let value = try decoder.unbox(elements[currentIndex].stringValue, as: Int16.self)
            currentIndex += 1
            return value
        }

        mutating func decode(_ type: Int32.Type) throws -> Int32 {
            let value = try decoder.unbox(elements[currentIndex].stringValue, as: Int32.self)
            currentIndex += 1
            return value
        }

        mutating func decode(_ type: Int64.Type) throws -> Int64 {
            let value = try decoder.unbox(elements[currentIndex].stringValue, as: Int64.self)
            currentIndex += 1
            return value
        }

        mutating func decode(_ type: UInt.Type) throws -> UInt {
            let value = try decoder.unbox(elements[currentIndex].stringValue, as: UInt.self)
            currentIndex += 1
            return value
        }

        mutating func decode(_ type: UInt8.Type) throws -> UInt8 {
            let value = try decoder.unbox(elements[currentIndex].stringValue, as: UInt8.self)
            currentIndex += 1
            return value
        }

        mutating func decode(_ type: UInt16.Type) throws -> UInt16 {
            let value = try decoder.unbox(elements[currentIndex].stringValue, as: UInt16.self)
            currentIndex += 1
            return value
        }

        mutating func decode(_ type: UInt32.Type) throws -> UInt32 {
            let value = try decoder.unbox(elements[currentIndex].stringValue, as: UInt32.self)
            currentIndex += 1
            return value
        }

        mutating func decode(_ type: UInt64.Type) throws -> UInt64 {
            let value = try decoder.unbox(elements[currentIndex].stringValue, as: UInt64.self)
            currentIndex += 1
            return value
        }

        mutating func decode<T>(_ type: T.Type) throws -> T where T : Decodable {
            let decoder = _AWSXMLDecoder(elements[currentIndex], at:codingPath)
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
        return SVDC(elements[0], decoder:self)
    }

    struct SVDC : SingleValueDecodingContainer {
        var codingPath: [CodingKey] { return decoder.codingPath }
        let element : XMLElement
        let decoder : _AWSXMLDecoder

        init(_ element : XMLElement, decoder: _AWSXMLDecoder) {
            self.element = element
            self.decoder = decoder
        }

        func decodeNil() -> Bool {
            fatalError()
        }

        func decode(_ type: Bool.Type) throws -> Bool {
            return try decoder.unbox(element.stringValue, as: Bool.self)
        }

        func decode(_ type: String.Type) throws -> String {
            return try decoder.unbox(element.stringValue, as: String.self)
        }

        func decode(_ type: Double.Type) throws -> Double {
            return try decoder.unbox(element.stringValue, as: Double.self)
        }

        func decode(_ type: Float.Type) throws -> Float {
            return try decoder.unbox(element.stringValue, as: Float.self)
        }

        func decode(_ type: Int.Type) throws -> Int {
            return try decoder.unbox(element.stringValue, as: Int.self)
        }

        func decode(_ type: Int8.Type) throws -> Int8 {
            return try decoder.unbox(element.stringValue, as: Int8.self)
        }

        func decode(_ type: Int16.Type) throws -> Int16 {
            return try decoder.unbox(element.stringValue, as: Int16.self)
        }

        func decode(_ type: Int32.Type) throws -> Int32 {
            return try decoder.unbox(element.stringValue, as: Int32.self)
        }

        func decode(_ type: Int64.Type) throws -> Int64 {
            return try decoder.unbox(element.stringValue, as: Int64.self)
        }

        func decode(_ type: UInt.Type) throws -> UInt {
            return try decoder.unbox(element.stringValue, as: UInt.self)
        }

        func decode(_ type: UInt8.Type) throws -> UInt8 {
            return try decoder.unbox(element.stringValue, as: UInt8.self)
        }

        func decode(_ type: UInt16.Type) throws -> UInt16 {
            return try decoder.unbox(element.stringValue, as: UInt16.self)
        }

        func decode(_ type: UInt32.Type) throws -> UInt32 {
            return try decoder.unbox(element.stringValue, as: UInt32.self)
        }

        func decode(_ type: UInt64.Type) throws -> UInt64 {
            return try decoder.unbox(element.stringValue, as: UInt64.self)
        }

        func decode<T>(_ type: T.Type) throws -> T where T : Decodable {
            let decoder = _AWSXMLDecoder(element, at:codingPath)
            return try T(from: decoder)
        }

    }

    func unbox(_ optionalValue : String?, as type: Bool.Type) throws -> Bool {
        guard let value = optionalValue, let unboxValue = Bool(value) else { throw DecodingError._typeMismatch(at: codingPath, expectation: Bool.self, reality: optionalValue ?? "nil") }
        return unboxValue
    }

    func unbox(_ optionalValue : String?, as type: String.Type) throws -> String {
        guard let unboxValue = optionalValue else { throw DecodingError._typeMismatch(at: codingPath, expectation: Bool.self, reality: optionalValue ?? "nil") }
        return unboxValue
    }

    func unbox(_ optionalValue : String?, as type: Double.Type) throws -> Double {
        guard let value = optionalValue, let unboxValue = Double(value) else { throw DecodingError._typeMismatch(at: codingPath, expectation: Double.self, reality: optionalValue ?? "nil") }
        return unboxValue
    }

    func unbox(_ optionalValue : String?, as type: Float.Type) throws -> Float {
        guard let value = optionalValue, let unboxValue = Float(value) else { throw DecodingError._typeMismatch(at: codingPath, expectation: Float.self, reality: optionalValue ?? "nil") }
        return unboxValue
    }

    func unbox(_ optionalValue : String?, as type: Int.Type) throws -> Int {
        guard let value = optionalValue, let unboxValue = Int(value) else { throw DecodingError._typeMismatch(at: codingPath, expectation: Int.self, reality: optionalValue ?? "nil") }
        return unboxValue
    }

    func unbox(_ optionalValue : String?, as type: Int8.Type) throws -> Int8 {
        guard let value = optionalValue, let unboxValue = Int8(value) else { throw DecodingError._typeMismatch(at: codingPath, expectation: Int8.self, reality: optionalValue ?? "nil") }
        return unboxValue
    }

    func unbox(_ optionalValue : String?, as type: Int16.Type) throws -> Int16 {
        guard let value = optionalValue, let unboxValue = Int16(value) else { throw DecodingError._typeMismatch(at: codingPath, expectation: Int16.self, reality: optionalValue ?? "nil") }
        return unboxValue
    }

    func unbox(_ optionalValue : String?, as type: Int32.Type) throws -> Int32 {
        guard let value = optionalValue, let unboxValue = Int32(value) else { throw DecodingError._typeMismatch(at: codingPath, expectation: Int32.self, reality: optionalValue ?? "nil") }
        return unboxValue
    }

    func unbox(_ optionalValue : String?, as type: Int64.Type) throws -> Int64 {
        guard let value = optionalValue, let unboxValue = Int64(value) else { throw DecodingError._typeMismatch(at: codingPath, expectation: Int64.self, reality: optionalValue ?? "nil") }
        return unboxValue
    }

    func unbox(_ optionalValue : String?, as type: UInt.Type) throws -> UInt {
        guard let value = optionalValue, let unboxValue = UInt(value) else { throw DecodingError._typeMismatch(at: codingPath, expectation: UInt.self, reality: optionalValue ?? "nil") }
        return unboxValue
    }

    func unbox(_ optionalValue : String?, as type: UInt8.Type) throws -> UInt8 {
        guard let value = optionalValue, let unboxValue = UInt8(value) else { throw DecodingError._typeMismatch(at: codingPath, expectation: UInt8.self, reality: optionalValue ?? "nil") }
        return unboxValue
    }

    func unbox(_ optionalValue : String?, as type: UInt16.Type) throws -> UInt16 {
        guard let value = optionalValue, let unboxValue = UInt16(value) else { throw DecodingError._typeMismatch(at: codingPath, expectation: UInt16.self, reality: optionalValue ?? "nil") }
        return unboxValue
    }

    func unbox(_ optionalValue : String?, as type: UInt32.Type) throws -> UInt32 {
        guard let value = optionalValue, let unboxValue = UInt32(value) else { throw DecodingError._typeMismatch(at: codingPath, expectation: UInt32.self, reality: optionalValue ?? "nil") }
        return unboxValue
    }

    func unbox(_ optionalValue : String?, as type: UInt64.Type) throws -> UInt64 {
        guard let value = optionalValue, let unboxValue = UInt64(value) else { throw DecodingError._typeMismatch(at: codingPath, expectation: UInt64.self, reality: optionalValue ?? "nil") }
        return unboxValue
    }
}
