//
//  XMLDecoder.swift
//  AWSSDKSwift
//
//  Created by Adam Fowler on 2019/05/01.
//
//
import Foundation

public class AWSXMLEncoder {
    public init() {}
    
    open func encode<T : Encodable>(_ value: T, name: String? = nil) throws -> XMLElement {
        let encoder = _AWSXMLEncoder(at: [_XMLKey(stringValue:name ?? "\(type(of: value))", intValue: nil)])
        try value.encode(to: encoder)
        
        guard let element = encoder.element else { throw EncodingError.invalidValue(T.self, EncodingError.Context(codingPath: [], debugDescription: "Failed to create any XML elements"))}
        return element
    }
}

struct _AWSXMLEncoderStorage {
    /// the container stack
    private var containers : [XMLElement] = []

    /// initializes self with no containers
    init() {}
    
    /// return the container at the top of the storage
    var topContainer : XMLElement? { return containers.last }
    
    /// push a new container onto the storage
    mutating func push(container: XMLElement) { containers.append(container) }
    
    /// pop a container from the storage
    mutating func popContainer() { containers.removeLast() }
}

class _AWSXMLEncoder : Encoder {
    // MARK: Properties
    
    /// the encoder's storage
    var storage : _AWSXMLEncoderStorage

    /// the path to the current point in encoding
    var codingPath: [CodingKey]
    
    /// contextual user-provided information for use during encoding
    var userInfo: [CodingUserInfoKey : Any] = [:]
    
    /// the top level key
    var currentKey : String { return codingPath.last!.stringValue }
    
    /// the top level xml element
    var element : XMLElement? { return storage.topContainer }

    // MARK: - Initialization
    init(at codingPath: [CodingKey] = []) {
        self.codingPath = codingPath
        self.storage = _AWSXMLEncoderStorage()
    }
    
    // MARK: - Encoder methods
    
    func container<Key>(keyedBy type: Key.Type) -> KeyedEncodingContainer<Key> where Key : CodingKey {
        let newElement = XMLElement(name: currentKey)
        storage.topContainer?.addChild(newElement)
        storage.push(container: newElement)
        return KeyedEncodingContainer(KEC(newElement, encoder:self))
    }
    
    struct KEC<Key: CodingKey> : KeyedEncodingContainerProtocol {
        let encoder : _AWSXMLEncoder
        let element : XMLElement
        var codingPath: [CodingKey] { return encoder.codingPath }
        
        init(_ element : XMLElement, encoder: _AWSXMLEncoder) {
            self.encoder = encoder
            self.element = element
        }
        
        func encodeNil(forKey key: Key) throws {
        }
        
        func encode(_ value: Bool, forKey key: Key) throws {
            let childElement = XMLElement(name: key.stringValue, stringValue: value.description)
            element.addChild(childElement)
        }
        
        func encode(_ value: String, forKey key: Key) throws {
            let childElement = XMLElement(name: key.stringValue, stringValue: value)
            element.addChild(childElement)
        }
        
        func encode(_ value: Double, forKey key: Key) throws {
            let childElement = XMLElement(name: key.stringValue, stringValue: NSNumber(value:value).description)
            element.addChild(childElement)
        }
        
        func encode(_ value: Float, forKey key: Key) throws {
            let childElement = XMLElement(name: key.stringValue, stringValue: NSNumber(value:value).description)
            element.addChild(childElement)
        }
        
        func encode(_ value: Int, forKey key: Key) throws {
            let childElement = XMLElement(name: key.stringValue, stringValue: NSNumber(value:value).description)
            element.addChild(childElement)
        }
        
        func encode(_ value: Int8, forKey key: Key) throws {
            let childElement = XMLElement(name: key.stringValue, stringValue: NSNumber(value:value).description)
            element.addChild(childElement)
        }
        
        func encode(_ value: Int16, forKey key: Key) throws {
            let childElement = XMLElement(name: key.stringValue, stringValue: NSNumber(value:value).description)
            element.addChild(childElement)
        }
        
        func encode(_ value: Int32, forKey key: Key) throws {
            let childElement = XMLElement(name: key.stringValue, stringValue: NSNumber(value:value).description)
            element.addChild(childElement)
        }
        
        func encode(_ value: Int64, forKey key: Key) throws {
            let childElement = XMLElement(name: key.stringValue, stringValue: NSNumber(value:value).description)
            element.addChild(childElement)
        }
        
        func encode(_ value: UInt, forKey key: Key) throws {
            let childElement = XMLElement(name: key.stringValue, stringValue: NSNumber(value:value).description)
            element.addChild(childElement)
        }
        
        func encode(_ value: UInt8, forKey key: Key) throws {
            let childElement = XMLElement(name: key.stringValue, stringValue: NSNumber(value:value).description)
            element.addChild(childElement)
        }
        
        func encode(_ value: UInt16, forKey key: Key) throws {
            let childElement = XMLElement(name: key.stringValue, stringValue: NSNumber(value:value).description)
            element.addChild(childElement)
        }
        
        func encode(_ value: UInt32, forKey key: Key) throws {
            let childElement = XMLElement(name: key.stringValue, stringValue: NSNumber(value:value).description)
            element.addChild(childElement)
        }
        
        func encode(_ value: UInt64, forKey key: Key) throws {
            let childElement = XMLElement(name: key.stringValue, stringValue: NSNumber(value:value).description)
            element.addChild(childElement)
        }
        
        func encode<T>(_ value: T, forKey key: Key) throws where T : Encodable {
            self.encoder.codingPath.append(key)
            defer { self.encoder.codingPath.removeLast() }

            try value.encode(to: encoder)

            encoder.storage.popContainer()
        }
        
        func nestedContainer<NestedKey>(keyedBy keyType: NestedKey.Type, forKey key: Key) -> KeyedEncodingContainer<NestedKey> where NestedKey : CodingKey {
            fatalError()
        }
        
        func nestedUnkeyedContainer(forKey key: Key) -> UnkeyedEncodingContainer {
            fatalError()
        }
        
        func superEncoder() -> Encoder {
            fatalError()
        }
        
        func superEncoder(forKey key: Key) -> Encoder {
            fatalError()
        }
        
        
    }
    
    func unkeyedContainer() -> UnkeyedEncodingContainer {
        // Need to add support for non-flattened arrays here. Create an XML Element to contain them
        var arrayElement = element
        if arrayElement == nil {
            arrayElement = XMLElement(name:currentKey)
        }
        storage.push(container: arrayElement!)
        return UKEC(arrayElement!, referencing:self)
    }
    
    struct UKEC : UnkeyedEncodingContainer {
        
        let encoder : _AWSXMLEncoder
        let element : XMLElement
        var codingPath: [CodingKey] { return encoder.codingPath }
        var count : Int

        init(_ element : XMLElement, referencing encoder: _AWSXMLEncoder) {
            self.element = element
            self.encoder = encoder
            self.count = 0
        }
        
        func encode(_ value: Bool) throws {
            let childElement = XMLElement(name: encoder.currentKey, stringValue: value.description)
            element.addChild(childElement)
        }
        
        func encodeNil() throws {
        }
        
        func encode(_ value: String) throws {
            let childElement = XMLElement(name: encoder.currentKey, stringValue: value)
            element.addChild(childElement)
        }
        
        func encode(_ value: Double) throws {
            let childElement = XMLElement(name: encoder.currentKey, stringValue: NSNumber(value: value).description)
            element.addChild(childElement)
        }
        
        func encode(_ value: Float) throws {
            let childElement = XMLElement(name: encoder.currentKey, stringValue: NSNumber(value: value).description)
            element.addChild(childElement)

        }
        
        func encode(_ value: Int) throws {
            let childElement = XMLElement(name: encoder.currentKey, stringValue: NSNumber(value: value).description)
            element.addChild(childElement)
        }
        
        func encode(_ value: Int8) throws {
            let childElement = XMLElement(name: encoder.currentKey, stringValue: NSNumber(value: value).description)
            element.addChild(childElement)
        }
        
        func encode(_ value: Int16) throws {
            let childElement = XMLElement(name: encoder.currentKey, stringValue: NSNumber(value: value).description)
            element.addChild(childElement)
        }
        
        func encode(_ value: Int32) throws {
            let childElement = XMLElement(name: encoder.currentKey, stringValue: NSNumber(value: value).description)
            element.addChild(childElement)

        }
        
        func encode(_ value: Int64) throws {
            let childElement = XMLElement(name: encoder.currentKey, stringValue: NSNumber(value: value).description)
            element.addChild(childElement)
        }
        
        func encode(_ value: UInt) throws {
            let childElement = XMLElement(name: encoder.currentKey, stringValue: NSNumber(value: value).description)
            element.addChild(childElement)
        }
        
        func encode(_ value: UInt8) throws {
            let childElement = XMLElement(name: encoder.currentKey, stringValue: NSNumber(value: value).description)
            element.addChild(childElement)
        }
        
        func encode(_ value: UInt16) throws {
            let childElement = XMLElement(name: encoder.currentKey, stringValue: NSNumber(value: value).description)
            element.addChild(childElement)
        }
        
        func encode(_ value: UInt32) throws {
            let childElement = XMLElement(name: encoder.currentKey, stringValue: NSNumber(value: value).description)
            element.addChild(childElement)
        }
        
        func encode(_ value: UInt64) throws {
            let childElement = XMLElement(name: encoder.currentKey, stringValue: NSNumber(value: value).description)
            element.addChild(childElement)
        }
        
        func encode<T>(_ value: T) throws where T : Encodable {
            try value.encode(to: encoder)
            encoder.storage.popContainer()
        }
        
        func nestedContainer<NestedKey>(keyedBy keyType: NestedKey.Type) -> KeyedEncodingContainer<NestedKey> where NestedKey : CodingKey {
            fatalError()
        }
        
        func nestedUnkeyedContainer() -> UnkeyedEncodingContainer {
            fatalError()
        }
        
        func superEncoder() -> Encoder {
            fatalError()
        }
        
    }
    
    func singleValueContainer() -> SingleValueEncodingContainer {
        storage.push(container: element!)
        return self
    }

}

extension _AWSXMLEncoder : SingleValueEncodingContainer {
    
    func encodeNil() throws {
        //            fatalError()
    }
    
    func encode(_ value: Bool) throws {
        let childNode = XMLElement(name: currentKey, stringValue: value.description)
        element?.addChild(childNode)
    }
    
    func encode(_ value: String) throws {
        let childNode = XMLElement(name: currentKey, stringValue: value)
        element?.addChild(childNode)
    }
    
    func encode(_ value: Double) throws {
        let childNode = XMLElement(name: currentKey, stringValue: NSNumber(value:value).description)
        element?.addChild(childNode)
    }
    
    func encode(_ value: Float) throws {
        let childNode = XMLElement(name: currentKey, stringValue: NSNumber(value:value).description)
        element?.addChild(childNode)
    }
    
    func encode(_ value: Int) throws {
        let childNode = XMLElement(name: currentKey, stringValue: NSNumber(value:value).description)
        element?.addChild(childNode)
    }
    
    func encode(_ value: Int8) throws {
        let childNode = XMLElement(name: currentKey, stringValue: NSNumber(value:value).description)
        element?.addChild(childNode)
    }
    
    func encode(_ value: Int16) throws {
        let childNode = XMLElement(name: currentKey, stringValue: NSNumber(value:value).description)
        element?.addChild(childNode)
    }
    
    func encode(_ value: Int32) throws {
        let childNode = XMLElement(name: currentKey, stringValue: NSNumber(value:value).description)
        element?.addChild(childNode)
    }
    
    func encode(_ value: Int64) throws {
        let childNode = XMLElement(name: currentKey, stringValue: NSNumber(value:value).description)
        element?.addChild(childNode)
    }
    
    func encode(_ value: UInt) throws {
        let childNode = XMLElement(name: currentKey, stringValue: NSNumber(value:value).description)
        element?.addChild(childNode)
    }
    
    func encode(_ value: UInt8) throws {
        let childNode = XMLElement(name: currentKey, stringValue: NSNumber(value:value).description)
        element?.addChild(childNode)
    }
    
    func encode(_ value: UInt16) throws {
        let childNode = XMLElement(name: currentKey, stringValue: NSNumber(value:value).description)
        element?.addChild(childNode)
    }
    
    func encode(_ value: UInt32) throws {
        let childNode = XMLElement(name: currentKey, stringValue: NSNumber(value:value).description)
        element?.addChild(childNode)
    }
    
    func encode(_ value: UInt64) throws {
        let childNode = XMLElement(name: currentKey, stringValue: NSNumber(value:value).description)
        element?.addChild(childNode)
    }
    
    func encode<T>(_ value: T) throws where T : Encodable {
        try value.encode(to: self)
        storage.popContainer()
    }
}

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

