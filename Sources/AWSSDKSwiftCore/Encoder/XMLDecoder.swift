//
//  XMLDecoder.swift
//  AWSSDKSwift
//
//  Created by Adam Fowler on 2019/05/01.
//
//
import Foundation

/// rules for encoding/decoding containers like arrays and dictionaries.
public enum XMLContainerCoding {
    /// default case, flat arrays and coding dictionaries like all other codable structures
    case `default`
    
    /// case for coding arrays. where there is an enclosing xml element and each array element has name is defined by element. eg <array><member>1</member><member>2</member></array>
    case array(entry: String)
    
    /// case for coding dictionaries where key and value are stored in separate elements and these can be either stored as children of the dictionary element or as children of a enclosing entry element which is then stored under the dictionary element eg <dict><entry><key>name</key><value>John Smith</value></entry><entry>...</entry>...</dict>
    case dictionary(entry: String?, key: String, value: String)
}

/// protocol to return XMLContainerCoding values. To control how the child elements of a Codable class are encoded inherit from this and return coding values for each
public protocol XMLContainerCodingMap {
    static func getXMLContainerCoding(for key: CodingKey) -> XMLContainerCoding
}

/// The wrapper class for decoding Codable classes from XMLElements
public class XMLDecoder {
    
    /// The strategy to use for decoding `Date` values.
    public enum DateDecodingStrategy {
        /// Defer to `Date` for decoding. This is the default strategy.
        case deferredToDate
        
        /// Decode the `Date` as a UNIX timestamp from a JSON number.
        case secondsSince1970
        
        /// Decode the `Date` as UNIX millisecond timestamp from a JSON number.
        case millisecondsSince1970
        
        /// Decode the `Date` as an ISO-8601-formatted string (in RFC 3339 format).
        @available(macOS 10.12, iOS 10.0, watchOS 3.0, tvOS 10.0, *)
        case iso8601
        
        /// Decode the `Date` as a string parsed by the given formatter.
        case formatted(DateFormatter)
        
        /// Decode the `Date` as a custom value decoded by the given closure.
        case custom((_ decoder: Decoder) throws -> Date)
    }
    
    /// The strategy to use for decoding `Data` values.
    public enum DataDecodingStrategy {
        /// Defer to `Data` for decoding.
        case deferredToData
        
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

    /// The strategy to use in decoding dates. Defaults to `.deferredToDate`.
    open var dateDecodingStrategy: DateDecodingStrategy = .deferredToDate
    
    /// The strategy to use in decoding binary data. Defaults to `.raw`.
    open var dataDecodingStrategy: DataDecodingStrategy = .base64
    
    /// The strategy to use in decoding non-conforming numbers. Defaults to `.throw`.
    open var nonConformingFloatDecodingStrategy: NonConformingFloatDecodingStrategy = .throw
    
    /// Contextual user-provided information for use during decoding.
    open var userInfo: [CodingUserInfoKey : Any] = [:]
    
    /// Options set on the top-level encoder to pass down the decoding hierarchy.
    fileprivate struct _Options {
        let dateDecodingStrategy: DateDecodingStrategy
        let dataDecodingStrategy: DataDecodingStrategy
        let nonConformingFloatDecodingStrategy: NonConformingFloatDecodingStrategy
        let userInfo: [CodingUserInfoKey : Any]
    }
    
    /// The options set on the top-level decoder.
    fileprivate var options: _Options {
        return _Options(dateDecodingStrategy: dateDecodingStrategy,
                        dataDecodingStrategy: dataDecodingStrategy,
                        nonConformingFloatDecodingStrategy: nonConformingFloatDecodingStrategy,
                        userInfo: userInfo)
    }
    

    public init() {}

    /// decode a Codable class from XML
    public func decode<T : Decodable>(_ type: T.Type, from xml: XMLElement) throws -> T {
        let containerCodingMapType = type as? XMLContainerCodingMap.Type
        let decoder = _XMLDecoder(xml, options: self.options, containerCodingMapType: containerCodingMapType)
        let value = try T(from: decoder)
        return value
    }
}

extension XMLElement {
    func child(for string: String) -> XMLElement? {
        return (children ?? []).first(where: {$0.name == string}) as? XMLElement
    }

    func child(for key: CodingKey) -> XMLElement? {
        return child(for: key.stringValue)
    }
}

/// Storage for the XMLDecoder. Stores a stack of XMLElements
struct _XMLDecoderStorage {
    /// the container stack
    private var containers : [XMLElement] = []
    
    /// initializes self with no containers
    init() {}
    
    /// return the container at the top of the storage
    var topContainer : XMLElement? { return containers.last }
    
    /// push a new container onto the storage
    mutating func push(container: XMLElement) { containers.append(container) }
    
    /// pop a container from the storage
    @discardableResult mutating func popContainer() -> XMLElement { return containers.removeLast() }
}

/// Internal XMLDecoder class. Does all the heavy lifting
fileprivate class _XMLDecoder : Decoder {
    
    /// The decoder's storage.
    var storage : _XMLDecoderStorage
    
    /// Options set on the top-level decoder.
    let options: XMLDecoder._Options
    
    /// The path to the current point in encoding.
    var codingPath: [CodingKey]
    
    /// Contextual user-provided information for use during encoding.
    public var userInfo: [CodingUserInfoKey : Any] { return self.options.userInfo }
    
    /// Current element we are working with
    var element : XMLElement { return storage.topContainer! }

    /// the container coding map for the current element
    var containerCodingMapType : XMLContainerCodingMap.Type?
    
    /// the container encoding for the current element
    var containerCoding : XMLContainerCoding = .default

    public init(_ element : XMLElement, at codingPath: [CodingKey] = [], options: XMLDecoder._Options, containerCodingMapType: XMLContainerCodingMap.Type?) {
        self.storage = _XMLDecoderStorage()
        self.storage.push(container: element)
        self.codingPath = codingPath
        self.options = options
        self.containerCodingMapType = containerCodingMapType
    }

    public func container<Key>(keyedBy type: Key.Type) throws -> KeyedDecodingContainer<Key> where Key : CodingKey {
        return KeyedDecodingContainer(KDC(element, decoder: self))
    }

    struct KDC<Key: CodingKey> : KeyedDecodingContainerProtocol {
        var codingPath: [CodingKey] { return decoder.codingPath }
        var allKeys: [Key] = []
        var allValueElements: [String : XMLElement] = [:]
        let element : XMLElement
        let decoder : _XMLDecoder
        let expandedDictionary : Bool // are we decoding a dictionary of the form <entry><key></key><value></value></entry><entry>...

        public init(_ element : XMLElement, decoder: _XMLDecoder) {
            self.element = element
            self.decoder = decoder
            
            // based on the containerCoding, select the key and value XML elements
            switch decoder.containerCoding {
            case .dictionary(var entryName, let keyName, let valueName):
                // if entry name is NULL, look for key and value xml elements directly below the container xml element
                var element = element
                
                if entryName == nil {
                    entryName = element.name!
                    if let parent = element.parent as? XMLElement {
                        decoder.storage.popContainer()
                        decoder.storage.push(container: parent)
                        element = parent
                    }
                }
                let entries = element.elements(forName: entryName!)
                for entry in entries {
                    if let keyElement = entry.child(for: keyName), let valueElement = entry.child(for: valueName) {
                        guard let keyString = keyElement.stringValue else { continue }
                        if let key = Key(stringValue: keyString) {
                            allKeys.append(key)
                            // store value elements for later
                            allValueElements[keyString] = valueElement
                        }
                    }
                }

                expandedDictionary = true
                
            default:
                // all elements directly under the container xml element are considered. THe key is the name of the element and the value is the text attached to the element
                allKeys = element.children?.compactMap { (element: Foundation.XMLNode)->Key? in
                    if let name = element.name {
                        return Key(stringValue: name)
                    }
                    return nil
                    } ?? []
                expandedDictionary = false
            }
        }

        /// return if decoder has a value for a key
        func contains(_ key: Key) -> Bool {
            if expandedDictionary {
                return allValueElements[key.stringValue] != nil
            } else {
                return element.child(for: key) != nil
            }
        }

        /// get the XMLElment for a particular key
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

        func decodeNil(forKey key: Key) throws -> Bool {
            let child = try self.child(for: key)
            return child.attribute(forName: "nil") != nil
        }

        func decode(_ type: Bool.Type, forKey key: Key) throws -> Bool {
            let child = try self.child(for: key)
            return try decoder.unbox(child, as:Bool.self)
        }

        func decode(_ type: String.Type, forKey key: Key) throws -> String {
            let child = try self.child(for: key)
            return try decoder.unbox(child, as:String.self)
        }

        func decode(_ type: Double.Type, forKey key: Key) throws -> Double {
            let child = try self.child(for: key)
            return try decoder.unbox(child, as:Double.self)
        }

        func decode(_ type: Float.Type, forKey key: Key) throws -> Float {
            let child = try self.child(for: key)
            return try decoder.unbox(child, as:Float.self)
        }

        func decode(_ type: Int.Type, forKey key: Key) throws -> Int {
            let child = try self.child(for: key)
            return try decoder.unbox(child, as:Int.self)
        }

        func decode(_ type: Int8.Type, forKey key: Key) throws -> Int8 {
            let child = try self.child(for: key)
            return try decoder.unbox(child, as:Int8.self)
        }

        func decode(_ type: Int16.Type, forKey key: Key) throws -> Int16 {
            let child = try self.child(for: key)
            return try decoder.unbox(child, as:Int16.self)
        }

        func decode(_ type: Int32.Type, forKey key: Key) throws -> Int32 {
            let child = try self.child(for: key)
            return try decoder.unbox(child, as:Int32.self)
        }

        func decode(_ type: Int64.Type, forKey key: Key) throws -> Int64 {
            let child = try self.child(for: key)
            return try decoder.unbox(child, as:Int64.self)
        }

        func decode(_ type: UInt.Type, forKey key: Key) throws -> UInt {
            let child = try self.child(for: key)
            return try decoder.unbox(child, as:UInt.self)
        }

        func decode(_ type: UInt8.Type, forKey key: Key) throws -> UInt8 {
            let child = try self.child(for: key)
            return try decoder.unbox(child, as:UInt8.self)
        }

        func decode(_ type: UInt16.Type, forKey key: Key) throws -> UInt16 {
            let child = try self.child(for: key)
            return try decoder.unbox(child, as:UInt16.self)
        }

        func decode(_ type: UInt32.Type, forKey key: Key) throws -> UInt32 {
            let child = try self.child(for: key)
            return try decoder.unbox(child, as:UInt32.self)
        }

        func decode(_ type: UInt64.Type, forKey key: Key) throws -> UInt64 {
            let child = try self.child(for: key)
            return try decoder.unbox(child, as:UInt64.self)
        }

        func decode<T>(_ type: T.Type, forKey key: Key) throws -> T where T : Decodable {
            // store containerCoding to reset at the exit of thie function
            let prevContainerCoding = decoder.containerCoding
            defer { decoder.containerCoding = prevContainerCoding }
            self.decoder.codingPath.append(key)
            defer { self.decoder.codingPath.removeLast() }

            // set containerCoding
            decoder.containerCoding = decoder.containerCodingMapType?.getXMLContainerCoding(for:key) ?? .default

            let element = try self.child(for:key)
            return try decoder.unbox(element, as:T.self)
        }

        func nestedContainer<NestedKey>(keyedBy type: NestedKey.Type, forKey key: Key) throws -> KeyedDecodingContainer<NestedKey> where NestedKey : CodingKey {
            self.decoder.codingPath.append(key)
            defer { self.decoder.codingPath.removeLast() }
            
            let child = try self.child(for: key)
            
            let container = KDC<NestedKey>(child, decoder:self.decoder)
            return KeyedDecodingContainer(container)
        }

        func nestedUnkeyedContainer(forKey key: Key) throws -> UnkeyedDecodingContainer {
            self.decoder.codingPath.append(key)
            defer { self.decoder.codingPath.removeLast() }
            
            return UKDC(element, decoder: self.decoder)
        }

        private func _superDecoder(forKey key: __owned CodingKey) throws -> Decoder {
            self.decoder.codingPath.append(key)
            defer { self.decoder.codingPath.removeLast() }
            
            let child = try self.child(for: key)
            return _XMLDecoder(child, at: self.decoder.codingPath, options: self.decoder.options, containerCodingMapType: decoder.containerCodingMapType)
        }
        
       func superDecoder() throws -> Decoder {
        return try _superDecoder(forKey: _XMLKey.super)
        }

        func superDecoder(forKey key: Key) throws -> Decoder {
            return try _superDecoder(forKey: key)
        }

    }

    public func unkeyedContainer() throws -> UnkeyedDecodingContainer {
        return UKDC(element, decoder: self)
    }

    struct UKDC : UnkeyedDecodingContainer {
        var codingPath: [CodingKey] { return decoder.codingPath }
        var currentIndex: Int = 0
        let elements : [XMLElement]
        let decoder : _XMLDecoder

        init(_ element: XMLElement, decoder: _XMLDecoder) {
            // build array of elements based on the container coding
            switch decoder.containerCoding {
            case .array(let member):
                // array is built from child xmlelements with name member
                self.elements = element.elements(forName: member)
                
            case .dictionary(let entry, let key, let value):
                // dictionaries with non string keys are processed with an UnkeyedDecodingContainer. With elements alternating between key and value
                var elements : [XMLElement] = []
                if let entry = entry {
                    for entryChild in element.elements(forName: entry) {
                        let keyElement = entryChild.child(for: key)
                        let entryElement = entryChild.child(for: value)
                        if keyElement != nil && entryElement != nil {
                            elements.append(keyElement!)
                            elements.append(entryElement!)
                        }
                    }
                } else {
                    for child in element.children ?? [] {
                        if let childElement = child as? XMLElement {
                            if childElement.name == key || childElement.name == value {
                                elements.append(childElement)
                            }
                        }
                    }
                }
                self.elements = elements
                
            default:
                if let parent = element.parent as? XMLElement {
                    decoder.storage.popContainer()
                    decoder.storage.push(container: parent)
                    self.elements = parent.elements(forName: decoder.codingPath.last!.stringValue)
                } else {
                    self.elements = []
                }
                
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
            let value = try decoder.unbox(elements[currentIndex], as: Bool.self)
            currentIndex += 1
            return value
        }

        mutating func decode(_ type: String.Type) throws -> String {
            let value = try decoder.unbox(elements[currentIndex], as: String.self)
            currentIndex += 1
            return value
        }

        mutating func decode(_ type: Double.Type) throws -> Double {
            let value = try decoder.unbox(elements[currentIndex], as: Double.self)
            currentIndex += 1
            return value
        }

        mutating func decode(_ type: Float.Type) throws -> Float {
            let value = try decoder.unbox(elements[currentIndex], as: Float.self)
            currentIndex += 1
            return value
        }

        mutating func decode(_ type: Int.Type) throws -> Int {
            let value = try decoder.unbox(elements[currentIndex], as: Int.self)
            currentIndex += 1
            return value
        }

        mutating func decode(_ type: Int8.Type) throws -> Int8 {
            let value = try decoder.unbox(elements[currentIndex], as: Int8.self)
            currentIndex += 1
            return value
        }

        mutating func decode(_ type: Int16.Type) throws -> Int16 {
            let value = try decoder.unbox(elements[currentIndex], as: Int16.self)
            currentIndex += 1
            return value
        }

        mutating func decode(_ type: Int32.Type) throws -> Int32 {
            let value = try decoder.unbox(elements[currentIndex], as: Int32.self)
            currentIndex += 1
            return value
        }

        mutating func decode(_ type: Int64.Type) throws -> Int64 {
            let value = try decoder.unbox(elements[currentIndex], as: Int64.self)
            currentIndex += 1
            return value
        }

        mutating func decode(_ type: UInt.Type) throws -> UInt {
            let value = try decoder.unbox(elements[currentIndex], as: UInt.self)
            currentIndex += 1
            return value
        }

        mutating func decode(_ type: UInt8.Type) throws -> UInt8 {
            let value = try decoder.unbox(elements[currentIndex], as: UInt8.self)
            currentIndex += 1
            return value
        }

        mutating func decode(_ type: UInt16.Type) throws -> UInt16 {
            let value = try decoder.unbox(elements[currentIndex], as: UInt16.self)
            currentIndex += 1
            return value
        }

        mutating func decode(_ type: UInt32.Type) throws -> UInt32 {
            let value = try decoder.unbox(elements[currentIndex], as: UInt32.self)
            currentIndex += 1
            return value
        }

        mutating func decode(_ type: UInt64.Type) throws -> UInt64 {
            let value = try decoder.unbox(elements[currentIndex], as: UInt64.self)
            currentIndex += 1
            return value
        }

        mutating func decode<T>(_ type: T.Type) throws -> T where T : Decodable {
            let value = try decoder.unbox(elements[currentIndex], as:T.self)
            currentIndex += 1
            return value
        }

        mutating func nestedContainer<NestedKey>(keyedBy type: NestedKey.Type) throws -> KeyedDecodingContainer<NestedKey> where NestedKey : CodingKey {
            self.decoder.codingPath.append(_XMLKey(index: currentIndex))
            defer { self.decoder.codingPath.removeLast() }
            
            let child = elements[currentIndex]
            currentIndex += 1
            
            let container = KDC<NestedKey>(child, decoder:self.decoder)
            return KeyedDecodingContainer(container)
        }

        mutating func nestedUnkeyedContainer() throws -> UnkeyedDecodingContainer {
            self.decoder.codingPath.append(_XMLKey(index: currentIndex))
            defer { self.decoder.codingPath.removeLast() }
            
            currentIndex += 1

            return UKDC(elements[currentIndex], decoder: self.decoder)
        }

        mutating func superDecoder() throws -> Decoder {
            self.decoder.codingPath.append(_XMLKey(index: currentIndex))
            defer { self.decoder.codingPath.removeLast() }
            
            let child = elements[currentIndex]
            currentIndex += 1
            
            return _XMLDecoder(child, at: self.decoder.codingPath, options: self.decoder.options, containerCodingMapType: decoder.containerCodingMapType)
        }
    }

    public func singleValueContainer() throws -> SingleValueDecodingContainer {
        return SVDC(element, decoder:self)
    }

    struct SVDC : SingleValueDecodingContainer {
        var codingPath: [CodingKey] { return decoder.codingPath }
        let element : XMLElement
        let decoder : _XMLDecoder

        init(_ element : XMLElement, decoder: _XMLDecoder) {
            self.element = element
            self.decoder = decoder
        }

        func decodeNil() -> Bool {
            fatalError()
        }

        func decode(_ type: Bool.Type) throws -> Bool {
            return try decoder.unbox(element, as: Bool.self)
        }

        func decode(_ type: String.Type) throws -> String {
            return try decoder.unbox(element, as: String.self)
        }

        func decode(_ type: Double.Type) throws -> Double {
            return try decoder.unbox(element, as: Double.self)
        }

        func decode(_ type: Float.Type) throws -> Float {
            return try decoder.unbox(element, as: Float.self)
        }

        func decode(_ type: Int.Type) throws -> Int {
            return try decoder.unbox(element, as: Int.self)
        }

        func decode(_ type: Int8.Type) throws -> Int8 {
            return try decoder.unbox(element, as: Int8.self)
        }

        func decode(_ type: Int16.Type) throws -> Int16 {
            return try decoder.unbox(element, as: Int16.self)
        }

        func decode(_ type: Int32.Type) throws -> Int32 {
            return try decoder.unbox(element, as: Int32.self)
        }

        func decode(_ type: Int64.Type) throws -> Int64 {
            return try decoder.unbox(element, as: Int64.self)
        }

        func decode(_ type: UInt.Type) throws -> UInt {
            return try decoder.unbox(element, as: UInt.self)
        }

        func decode(_ type: UInt8.Type) throws -> UInt8 {
            return try decoder.unbox(element, as: UInt8.self)
        }

        func decode(_ type: UInt16.Type) throws -> UInt16 {
            return try decoder.unbox(element, as: UInt16.self)
        }

        func decode(_ type: UInt32.Type) throws -> UInt32 {
            return try decoder.unbox(element, as: UInt32.self)
        }

        func decode(_ type: UInt64.Type) throws -> UInt64 {
            return try decoder.unbox(element, as: UInt64.self)
        }

        func decode<T>(_ type: T.Type) throws -> T where T : Decodable {
            return try decoder.unbox(element, as: T.self)
        }

    }

    func unbox(_ element : XMLElement, as type: Bool.Type) throws -> Bool {
        guard let value = element.stringValue, let unboxValue = Bool(value) else { throw DecodingError._typeMismatch(at: codingPath, expectation: Bool.self, reality: element.stringValue ?? "nil") }
        return unboxValue
    }

    func unbox(_ element : XMLElement, as type: String.Type) throws -> String {
        guard let unboxValue = element.stringValue else { throw DecodingError._typeMismatch(at: codingPath, expectation: Bool.self, reality: element.stringValue ?? "nil") }
        return unboxValue
    }

    func unbox(_ element : XMLElement, as type: Int.Type) throws -> Int {
        guard let value = element.stringValue, let unboxValue = Int(value) else { throw DecodingError._typeMismatch(at: codingPath, expectation: Int.self, reality: element.stringValue ?? "nil") }
        return unboxValue
    }

    func unbox(_ element : XMLElement, as type: Int8.Type) throws -> Int8 {
        guard let value = element.stringValue, let unboxValue = Int8(value) else { throw DecodingError._typeMismatch(at: codingPath, expectation: Int8.self, reality: element.stringValue ?? "nil") }
        return unboxValue
    }

    func unbox(_ element : XMLElement, as type: Int16.Type) throws -> Int16 {
        guard let value = element.stringValue, let unboxValue = Int16(value) else { throw DecodingError._typeMismatch(at: codingPath, expectation: Int16.self, reality: element.stringValue ?? "nil") }
        return unboxValue
    }

    func unbox(_ element : XMLElement, as type: Int32.Type) throws -> Int32 {
        guard let value = element.stringValue, let unboxValue = Int32(value) else { throw DecodingError._typeMismatch(at: codingPath, expectation: Int32.self, reality: element.stringValue ?? "nil") }
        return unboxValue
    }

    func unbox(_ element : XMLElement, as type: Int64.Type) throws -> Int64 {
        guard let value = element.stringValue, let unboxValue = Int64(value) else { throw DecodingError._typeMismatch(at: codingPath, expectation: Int64.self, reality: element.stringValue ?? "nil") }
        return unboxValue
    }

    func unbox(_ element : XMLElement, as type: UInt.Type) throws -> UInt {
        guard let value = element.stringValue, let unboxValue = UInt(value) else { throw DecodingError._typeMismatch(at: codingPath, expectation: UInt.self, reality: element.stringValue ?? "nil") }
        return unboxValue
    }

    func unbox(_ element : XMLElement, as type: UInt8.Type) throws -> UInt8 {
        guard let value = element.stringValue, let unboxValue = UInt8(value) else { throw DecodingError._typeMismatch(at: codingPath, expectation: UInt8.self, reality: element.stringValue ?? "nil") }
        return unboxValue
    }

    func unbox(_ element : XMLElement, as type: UInt16.Type) throws -> UInt16 {
        guard let value = element.stringValue, let unboxValue = UInt16(value) else { throw DecodingError._typeMismatch(at: codingPath, expectation: UInt16.self, reality: element.stringValue ?? "nil") }
        return unboxValue
    }

    func unbox(_ element : XMLElement, as type: UInt32.Type) throws -> UInt32 {
        guard let value = element.stringValue, let unboxValue = UInt32(value) else { throw DecodingError._typeMismatch(at: codingPath, expectation: UInt32.self, reality: element.stringValue ?? "nil") }
        return unboxValue
    }

    func unbox(_ element : XMLElement, as type: UInt64.Type) throws -> UInt64 {
        guard let value = element.stringValue, let unboxValue = UInt64(value) else { throw DecodingError._typeMismatch(at: codingPath, expectation: UInt64.self, reality: element.stringValue ?? "nil") }
        return unboxValue
    }

    func unbox(_ element : XMLElement, as type: Double.Type) throws -> Double {
        guard let value = element.stringValue, let unboxValue = Double(value) else { throw DecodingError._typeMismatch(at: codingPath, expectation: Double.self, reality: element.stringValue ?? "nil") }
        return unboxValue
    }
    
    func unbox(_ element : XMLElement, as type: Float.Type) throws -> Float {
        guard let value = element.stringValue, let unboxValue = Float(value) else { throw DecodingError._typeMismatch(at: codingPath, expectation: Float.self, reality: element.stringValue ?? "nil") }
        return unboxValue
    }
    
    /// get Date from XMLElement
    func unbox(_ element : XMLElement, as type: Date.Type) throws -> Date {
        switch self.options.dateDecodingStrategy {
        case .deferredToDate:
            self.storage.push(container: element)
            defer { self.storage.popContainer() }
            return try Date(from: self)
            
        case .secondsSince1970:
            let double = try self.unbox(element, as: Double.self)
            return Date(timeIntervalSince1970: double)
            
        case .millisecondsSince1970:
            let double = try self.unbox(element, as: Double.self)
            return Date(timeIntervalSince1970: double / 1000.0)
            
        case .iso8601:
            if #available(macOS 10.12, iOS 10.0, watchOS 3.0, tvOS 10.0, *) {
                let string = try self.unbox(element, as: String.self)
                guard let date = _iso8601Formatter.date(from: string) else {
                    throw DecodingError.dataCorrupted(DecodingError.Context(codingPath: self.codingPath, debugDescription: "Expected date string to be ISO8601-formatted."))
                }
                
                return date
            } else {
                fatalError("ISO8601DateFormatter is unavailable on this platform.")
            }
            
        case .formatted(let formatter):
            let string = try self.unbox(element, as: String.self)
            guard let date = formatter.date(from: string) else {
                throw DecodingError.dataCorrupted(DecodingError.Context(codingPath: self.codingPath, debugDescription: "Date string does not match format expected by formatter."))
            }
            
            return date
            
        case .custom(let closure):
            self.storage.push(container: element)
            defer { self.storage.popContainer() }
            return try closure(self)
        }
    }
    
    /// get Data from XMLElement
    fileprivate func unbox(_ element : XMLElement, as type: Data.Type) throws -> Data {
        switch self.options.dataDecodingStrategy {
        case .deferredToData:
            self.storage.push(container: element)
            defer { self.storage.popContainer() }
            return try Data(from: self)
            
        case .base64:
            guard let string = element.stringValue else {
                throw DecodingError._typeMismatch(at: self.codingPath, expectation: type, reality: element.stringValue ?? "nil")
            }
            
            guard let data = Data(base64Encoded: string) else {
                throw DecodingError.dataCorrupted(DecodingError.Context(codingPath: self.codingPath, debugDescription: "Encountered Data is not valid Base64."))
            }
            
            return data
            
        case .custom(let closure):
            self.storage.push(container: element)
            defer { self.storage.popContainer() }
            return try closure(self)
        }
    }
    
    /// get URL from XMLElement
    fileprivate func unbox(_ element : XMLElement, as type: URL.Type) throws -> URL {
        let urlString = try self.unbox(element, as: String.self)
        guard let url = URL(string: urlString) else {
            throw DecodingError._typeMismatch(at: self.codingPath, expectation: type, reality: element.stringValue ?? "nil")
        }
        return url
    }
    
    func unbox<T>(_ element : XMLElement, as type: T.Type) throws -> T where T : Decodable {
        return try unbox_(element, as: T.self) as! T
    }
    
    func unbox_(_ element : XMLElement, as type: Decodable.Type) throws -> Any {
        // store previous container coding map to revert on function exit
        let prevContainerCodingOwner = self.containerCodingMapType
        defer { self.containerCodingMapType = prevContainerCodingOwner }
        // set the current container coding map
        containerCodingMapType = type as? XMLContainerCodingMap.Type
        
        if type == Date.self || type == NSDate.self {
            return try self.unbox(element, as: Date.self)
        } else if type == Data.self || type == NSData.self {
            return try self.unbox(element, as: Data.self)
        } else if type == URL.self || type == NSURL.self {
            return try self.unbox(element, as: URL.self)
        } else {
            self.storage.push(container:element)
            defer { self.storage.popContainer() }
            return try type.init(from: self)
        }
    }
}


//===----------------------------------------------------------------------===//
// Shared Key Types
//===----------------------------------------------------------------------===//

fileprivate struct _XMLKey : CodingKey {
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
// Shared ISO8601 Date Formatter
//===----------------------------------------------------------------------===//

// NOTE: This value is implicitly lazy and _must_ be lazy. We're compiled against the latest SDK (w/ ISO8601DateFormatter), but linked against whichever Foundation the user has. ISO8601DateFormatter might not exist, so we better not hit this code path on an older OS.
@available(macOS 10.12, iOS 10.0, watchOS 3.0, tvOS 10.0, *)
fileprivate var _iso8601Formatter: ISO8601DateFormatter = {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = .withInternetDateTime
    return formatter
}()

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
    fileprivate static func _invalidFloatingPointValue<T : FloatingPoint>(_ value: T, at codingPath: [CodingKey]) -> EncodingError {
        let valueDescription: String
        if value == T.infinity {
            valueDescription = "\(T.self).infinity"
        } else if value == -T.infinity {
            valueDescription = "-\(T.self).infinity"
        } else {
            valueDescription = "\(T.self).nan"
        }
        
        let debugDescription = "Unable to encode \(valueDescription) directly. Use DictionaryEncoder.NonConformingFloatEncodingStrategy.convertToString to specify how the value should be encoded."
        return .invalidValue(value, EncodingError.Context(codingPath: codingPath, debugDescription: debugDescription))
    }
}

