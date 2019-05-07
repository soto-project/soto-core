import Foundation

public class AWSXMLEncoder {
    public init() {}
    
    open func encode<T : Encodable>(_ value: T, name: String? = nil) throws -> XMLElement {
        let encoder = _AWSXMLEncoder(name ?? "\(type(of: value))")
        try value.encode(to: encoder)
        return encoder.elements[0]
    }
}

class _AWSXMLEncoder : Encoder {
    let name : String
    var elements : [XMLElement] = []
    var codingPath: [CodingKey]
    var userInfo: [CodingUserInfoKey : Any] = [:]
    
    init(_ elementName : String, at codingPath: [CodingKey] = []) {
        self.name = elementName
        self.codingPath = codingPath
    }
    
    func container<Key>(keyedBy type: Key.Type) -> KeyedEncodingContainer<Key> where Key : CodingKey {
        let element = XMLElement(name: name)
        elements.append(element)
        return KeyedEncodingContainer(KEC(element, encoder:self))
    }
    
    struct KEC<Key: CodingKey> : KeyedEncodingContainerProtocol {
        let referencing : _AWSXMLEncoder
        let element : XMLElement
        var codingPath: [CodingKey] { return referencing.codingPath }
        
        init(_ element : XMLElement, encoder: _AWSXMLEncoder) {
            self.referencing = encoder
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
            self.referencing.codingPath.append(key)
            defer { self.referencing.codingPath.removeLast() }

            let encoder = _AWSXMLEncoder(key.stringValue, at: codingPath)
            try value.encode(to: encoder)
            for child in encoder.elements {
                element.addChild(child)
            }
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
        return UKEC(self)
    }
    
    struct UKEC : UnkeyedEncodingContainer {
        
        let referencing : _AWSXMLEncoder
        var codingPath: [CodingKey] { return referencing.codingPath }
        var count : Int

        init(_ encoder: _AWSXMLEncoder) {
            self.referencing = encoder
            self.count = 0
        }
        
        func encode(_ value: Bool) throws {
            let element = XMLElement(name: referencing.name, stringValue: value.description)
            referencing.elements.append(element)
        }
        
        func encodeNil() throws {
        }
        
        func encode(_ value: String) throws {
            let element = XMLElement(name: referencing.name, stringValue: value)
            referencing.elements.append(element)
        }
        
        func encode(_ value: Double) throws {
            let element = XMLElement(name: referencing.name, stringValue: NSNumber(value: value).description)
            referencing.elements.append(element)
        }
        
        func encode(_ value: Float) throws {
            let element = XMLElement(name: referencing.name, stringValue: NSNumber(value: value).description)
            referencing.elements.append(element)
        }
        
        func encode(_ value: Int) throws {
            let element = XMLElement(name: referencing.name, stringValue: NSNumber(value: value).description)
            referencing.elements.append(element)
        }
        
        func encode(_ value: Int8) throws {
            let element = XMLElement(name: referencing.name, stringValue: NSNumber(value: value).description)
            referencing.elements.append(element)
        }
        
        func encode(_ value: Int16) throws {
            let element = XMLElement(name: referencing.name, stringValue: NSNumber(value: value).description)
            referencing.elements.append(element)
        }
        
        func encode(_ value: Int32) throws {
            let element = XMLElement(name: referencing.name, stringValue: NSNumber(value: value).description)
            referencing.elements.append(element)
        }
        
        func encode(_ value: Int64) throws {
            let element = XMLElement(name: referencing.name, stringValue: NSNumber(value: value).description)
            referencing.elements.append(element)
        }
        
        func encode(_ value: UInt) throws {
            let element = XMLElement(name: referencing.name, stringValue: NSNumber(value: value).description)
            referencing.elements.append(element)
        }
        
        func encode(_ value: UInt8) throws {
            let element = XMLElement(name: referencing.name, stringValue: NSNumber(value: value).description)
            referencing.elements.append(element)
        }
        
        func encode(_ value: UInt16) throws {
            let element = XMLElement(name: referencing.name, stringValue: NSNumber(value: value).description)
            referencing.elements.append(element)
        }
        
        func encode(_ value: UInt32) throws {
            let element = XMLElement(name: referencing.name, stringValue: NSNumber(value: value).description)
            referencing.elements.append(element)
        }
        
        func encode(_ value: UInt64) throws {
            let element = XMLElement(name: referencing.name, stringValue: NSNumber(value: value).description)
            referencing.elements.append(element)
        }
        
        func encode<T>(_ value: T) throws where T : Encodable {
            let encoder = _AWSXMLEncoder(referencing.name, at: codingPath)
            try value.encode(to: encoder)
            referencing.elements.append(contentsOf:encoder.elements)
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
        return SVEC(self)
    }
    
    struct SVEC : SingleValueEncodingContainer {
        let referencing : _AWSXMLEncoder
        var codingPath: [CodingKey] { return referencing.codingPath }
        
        init(_ encoder : _AWSXMLEncoder) {
            self.referencing = encoder
        }
        
        func encodeNil() throws {
//            fatalError()
        }
        
        func encode(_ value: Bool) throws {
            let element = XMLElement(name: referencing.name, stringValue: value.description)
            referencing.elements.append(element)
        }
        
        func encode(_ value: String) throws {
            let element = XMLElement(name: referencing.name, stringValue: value)
            referencing.elements.append(element)
        }
        
        func encode(_ value: Double) throws {
            let element = XMLElement(name: referencing.name, stringValue: NSNumber(value:value).description)
            referencing.elements.append(element)
        }
        
        func encode(_ value: Float) throws {
            let element = XMLElement(name: referencing.name, stringValue: NSNumber(value:value).description)
            referencing.elements.append(element)
        }
        
        func encode(_ value: Int) throws {
            let element = XMLElement(name: referencing.name, stringValue: NSNumber(value:value).description)
            referencing.elements.append(element)
        }
        
        func encode(_ value: Int8) throws {
            let element = XMLElement(name: referencing.name, stringValue: NSNumber(value:value).description)
            referencing.elements.append(element)
        }
        
        func encode(_ value: Int16) throws {
            let element = XMLElement(name: referencing.name, stringValue: NSNumber(value:value).description)
            referencing.elements.append(element)
        }
        
        func encode(_ value: Int32) throws {
            let element = XMLElement(name: referencing.name, stringValue: NSNumber(value:value).description)
            referencing.elements.append(element)
        }
        
        func encode(_ value: Int64) throws {
            let element = XMLElement(name: referencing.name, stringValue: NSNumber(value:value).description)
            referencing.elements.append(element)
        }
        
        func encode(_ value: UInt) throws {
            let element = XMLElement(name: referencing.name, stringValue: NSNumber(value:value).description)
            referencing.elements.append(element)
        }
        
        func encode(_ value: UInt8) throws {
            let element = XMLElement(name: referencing.name, stringValue: NSNumber(value:value).description)
            referencing.elements.append(element)
        }
        
        func encode(_ value: UInt16) throws {
            let element = XMLElement(name: referencing.name, stringValue: NSNumber(value:value).description)
            referencing.elements.append(element)
        }
        
        func encode(_ value: UInt32) throws {
            let element = XMLElement(name: referencing.name, stringValue: NSNumber(value:value).description)
            referencing.elements.append(element)
        }
        
        func encode(_ value: UInt64) throws {
            let element = XMLElement(name: referencing.name, stringValue: NSNumber(value:value).description)
            referencing.elements.append(element)
        }
        
        func encode<T>(_ value: T) throws where T : Encodable {
            let encoder = _AWSXMLEncoder(referencing.name, at: codingPath)
            try value.encode(to: encoder)
            referencing.elements.append(contentsOf: encoder.elements)
        }
    }
}
