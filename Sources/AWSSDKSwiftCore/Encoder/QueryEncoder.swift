//
//  QueryEncoder.swift
//  AWSSDKSwift
//
//  Created by Adam Fowler on 2020/01/28.
//
//

/// A marker protocols used to determine whether a value is a `Dictionary` or an `Array`
fileprivate protocol _QueryDictionaryEncodableMarker { }
fileprivate protocol _QueryArrayEncodableMarker { }

extension Dictionary : _QueryDictionaryEncodableMarker where Value: Decodable { }
extension Array : _QueryArrayEncodableMarker where Element: Decodable { }

/// The wrapper class for encoding Codable classes to Query dictionary
public class QueryEncoder {

    /// The strategy to use for encoding Arrays
    open var arrayEncodingStrategy: XMLContainerCoding = .array(entry:nil)
    
    /// The strategy to use for encoding Dictionaries
    open var dictionaryEncodingStrategy: XMLContainerCoding = .structure
    
    /// override container encoding and flatten all the containers (needed for EC2, which reports unflattened containers when they are flattened)
    open var flattenContainers : Bool = false

    /// Contextual user-provided information for use during encoding.
    open var userInfo: [CodingUserInfoKey : Any] = [:]
    
    /// Options set on the top-level encoder to pass down the encoding hierarchy.
    fileprivate struct _Options {
        let arrayEncodingStrategy: XMLContainerCoding
        let dictionaryEncodingStrategy: XMLContainerCoding
        let flattenContainers: Bool
        let userInfo: [CodingUserInfoKey : Any]
    }
    
    /// The options set on the top-level encoder.
    fileprivate var options: _Options {
        return _Options(arrayEncodingStrategy: arrayEncodingStrategy,
                        dictionaryEncodingStrategy: dictionaryEncodingStrategy,
                        flattenContainers: flattenContainers,
                        userInfo: userInfo)
    }
    
    public init() {}
    
    open func encode<T : Encodable>(_ value: T, name: String? = nil) throws -> [String: Any] {
        // set the current container coding map
        let containerCodingMap = value as? XMLCodable
        let containerCodingMapType = containerCodingMap != nil ? type(of:containerCodingMap!) : nil
        let encoder = _QueryEncoder(options: options, containerCodingMapType: containerCodingMapType)
        try value.encode(to: encoder)
        return encoder.result
    }
}

/// Internal QueryEncoder class. Does all the heavy lifting
fileprivate class _QueryEncoder : Encoder {
    var codingPath: [CodingKey] {
        didSet { fullPath = codingPath.map {$0.stringValue}.joined(separator: ".") }
    }
    /// Path to element, elements are prefix with this value. As you add and remove codingPath elements this is re-constructed
    var fullPath: String
    
    /// options
    var options: QueryEncoder._Options

    /// resultant query array
    var result: [String: Any]

    /// the container coding map for the current element
    var containerCodingMapType : XMLCodable.Type?

    /// the container encoding for the current element
    var containerCoding : XMLContainerCoding = .default

    /// Contextual user-provided information for use during encoding.
    public var userInfo: [CodingUserInfoKey : Any] {
        return self.options.userInfo
    }
    
    /// Initialization
    /// - Parameters:
    ///   - options: options
    ///   - containerCodingMapType: Container encoding for the top level object
    init(options: QueryEncoder._Options, containerCodingMapType: XMLCodable.Type?) {
        self.options = options
        self.codingPath = []
        self.fullPath = ""
        self.result = [:]
        self.containerCodingMapType = containerCodingMapType
    }

    func container<Key>(keyedBy type: Key.Type) -> KeyedEncodingContainer<Key> where Key : CodingKey {
        return KeyedEncodingContainer(KEC(referencing:self))
    }
    
    struct KEC<Key: CodingKey> : KeyedEncodingContainerProtocol {
        var codingPath: [CodingKey] { return encoder.codingPath }
        let encoder: _QueryEncoder
        let entryPrefix: String
        let keyPrefix: String?
        let valuePrefix: String?
        var count = 1
        
        /// Initialization
        /// - Parameter referencing: encoder that created this
        init(referencing: _QueryEncoder) {
            self.encoder = referencing
            
            // extract dictionary/array encoding values
            if case .dictionary(let entryName, let keyName, let valueName) = encoder.containerCoding {
                if let entryName = entryName, encoder.options.flattenContainers == false {
                    entryPrefix = "\(entryName)."
                } else {
                    entryPrefix = ""
                }
                keyPrefix = keyName
                valuePrefix = valueName
            } else {
                entryPrefix = ""
                keyPrefix = nil
                valuePrefix = nil
            }
        }
        
        /// returns a prefix for any value we output.
        func prefix() -> String {
            return "\(entryPrefix)\(count)."
        }
        
        mutating func encode(_ value: Any, key: String) {
            // if we have both key and value prefixes we are outputting a dictionary so need to output two values
            if let keyPrefix = self.keyPrefix, let valuePrefix = self.valuePrefix {
                encoder.box(key, path: "\(prefix())\(keyPrefix)")
                encoder.box(value, path: "\(prefix())\(valuePrefix)")
            } else {
                encoder.box(value, path: key)
            }
            count += 1
        }
        
        mutating func encodeNil(forKey key: Key) throws { encode("", key: key.stringValue) }
        mutating func encode(_ value: Bool, forKey key: Key) throws { encode(value, key: key.stringValue) }
        mutating func encode(_ value: String, forKey key: Key) throws { encode(value, key: key.stringValue) }
        mutating func encode(_ value: Double, forKey key: Key) throws { encode(value, key: key.stringValue) }
        mutating func encode(_ value: Float, forKey key: Key) throws { encode(value, key: key.stringValue) }
        mutating func encode(_ value: Int, forKey key: Key) throws { encode(value, key: key.stringValue) }
        mutating func encode(_ value: Int8, forKey key: Key) throws { encode(value, key: key.stringValue) }
        mutating func encode(_ value: Int16, forKey key: Key) throws { encode(value, key: key.stringValue) }
        mutating func encode(_ value: Int32, forKey key: Key) throws { encode(value, key: key.stringValue) }
        mutating func encode(_ value: Int64, forKey key: Key) throws { encode(value, key: key.stringValue) }
        mutating func encode(_ value: UInt, forKey key: Key) throws { encode(value, key: key.stringValue) }
        mutating func encode(_ value: UInt8, forKey key: Key) throws { encode(value, key: key.stringValue) }
        mutating func encode(_ value: UInt16, forKey key: Key) throws { encode(value, key: key.stringValue) }
        mutating func encode(_ value: UInt32, forKey key: Key) throws { encode(value, key: key.stringValue) }
        mutating func encode(_ value: UInt64, forKey key: Key) throws { encode(value, key: key.stringValue) }
        
        mutating func encode<T: Encodable>(_ value: T, forKey key: Key) throws {
            if let keyPrefix = self.keyPrefix {
                encoder.box(key.stringValue, path: "\(prefix())\(keyPrefix)")
            }
            if let valuePrefix = self.valuePrefix {
                self.encoder.codingPath.append(_QueryKey(stringValue:"\(prefix())\(valuePrefix)", intValue: nil))
            } else {
                self.encoder.codingPath.append(key)
            }
            defer { self.encoder.codingPath.removeLast() }

            // set containerCoding
            if let containerCoding = encoder.containerCodingMapType?.getXMLContainerCoding(for:key) {
                encoder.containerCoding = containerCoding
            } else if value is _QueryDictionaryEncodableMarker {
                encoder.containerCoding = encoder.options.dictionaryEncodingStrategy
            } else if value is _QueryArrayEncodableMarker {
                encoder.containerCoding = encoder.options.arrayEncodingStrategy
            } else {
                encoder.containerCoding = .default
            }
            try encoder.box(value)
            
            count += 1
        }
        
        mutating func nestedContainer<NestedKey>(keyedBy keyType: NestedKey.Type, forKey key: Key) -> KeyedEncodingContainer<NestedKey> where NestedKey : CodingKey {
            self.encoder.codingPath.append(key)
            defer { self.encoder.codingPath.removeLast() }

            let container = KEC<NestedKey>(referencing: self.encoder)
            return KeyedEncodingContainer(container)
        }
        
        mutating func nestedUnkeyedContainer(forKey key: Key) -> UnkeyedEncodingContainer {
            self.encoder.codingPath.append(key)
            defer { self.encoder.codingPath.removeLast() }
            
            return UKEC(referencing: self.encoder)
        }
        
        mutating func superEncoder() -> Encoder {
            return encoder
        }
        
        mutating func superEncoder(forKey key: Key) -> Encoder {
            return encoder
        }
    }
    
    func unkeyedContainer() -> UnkeyedEncodingContainer {
        return UKEC(referencing: self)
    }
    
    struct UKEC : UnkeyedEncodingContainer {
        var codingPath: [CodingKey] { return encoder.codingPath }
        let encoder: _QueryEncoder
        var count: Int
        var entryPrefix: String = ""
        var suffixes: [String] = ["", ""]
        var prefixCount = 1

        init(referencing: _QueryEncoder) {
            self.encoder = referencing
            self.count = 0
 
            switch encoder.containerCoding {
            case .dictionary(let entryName, let keyName, let valueName):
                entryPrefix = ""
                if let entryName = entryName, encoder.options.flattenContainers == false {
                    entryPrefix = "\(entryName)."
                }
                suffixes = [".\(keyName)", ".\(valueName)"]
                prefixCount = 2
                
            case .array(let member):
                if let member = member, encoder.options.flattenContainers == false {
                    entryPrefix = "\(member)."
                }
            default:
                break
            }
        }

        mutating func getPath() -> String {
            // UKEC can be used to encode arrays or dictionaries where the key is not a base type eg an enum
            // if we are encoding a dictionary each alternating value is a key and then a value.
            let key = "\(entryPrefix)\((count/prefixCount)+1)\(suffixes[count&1])"
            count += 1
            return key
        }
        
        mutating func encodeNil() throws { encoder.box("", path: getPath()) }
        mutating func encode(_ value: Bool) throws { encoder.box(value, path: getPath()) }
        mutating func encode(_ value: String) throws { encoder.box(value, path: getPath()) }
        mutating func encode(_ value: Double) throws { encoder.box(value, path: getPath()) }
        mutating func encode(_ value: Float) throws { encoder.box(value, path: getPath()) }
        mutating func encode(_ value: Int) throws { encoder.box(value, path: getPath()) }
        mutating func encode(_ value: Int8) throws { encoder.box(value, path: getPath()) }
        mutating func encode(_ value: Int16) throws { encoder.box(value, path: getPath()) }
        mutating func encode(_ value: Int32) throws { encoder.box(value, path: getPath()) }
        mutating func encode(_ value: Int64) throws { encoder.box(value, path: getPath()) }
        mutating func encode(_ value: UInt) throws { encoder.box(value, path: getPath()) }
        mutating func encode(_ value: UInt8) throws { encoder.box(value, path: getPath()) }
        mutating func encode(_ value: UInt16) throws { encoder.box(value, path: getPath()) }
        mutating func encode(_ value: UInt32) throws { encoder.box(value, path: getPath()) }
        mutating func encode(_ value: UInt64) throws { encoder.box(value, path: getPath()) }
        
        mutating func encode<T: Encodable>(_ value: T) throws  {
            self.encoder.codingPath.append(_QueryKey(stringValue: getPath(), intValue: count))
            defer { self.encoder.codingPath.removeLast() }

            if value is _QueryDictionaryEncodableMarker {
                encoder.containerCoding = .structure
            } else if value is _QueryArrayEncodableMarker {
                encoder.containerCoding = .array(entry:nil)
            } else {
                encoder.containerCoding = .default
            }
            
            try encoder.box(value)
        }
        
        mutating func nestedContainer<NestedKey>(keyedBy keyType: NestedKey.Type) -> KeyedEncodingContainer<NestedKey> where NestedKey : CodingKey {
            let container = KEC<NestedKey>(referencing: self.encoder)
            return KeyedEncodingContainer(container)
        }
        
        mutating func nestedUnkeyedContainer() -> UnkeyedEncodingContainer {
            return UKEC(referencing: self.encoder)
        }
        
        mutating func superEncoder() -> Encoder {
            return encoder
        }
    }
}

extension _QueryEncoder : SingleValueEncodingContainer {
    func encodeNil() throws {
        box("", path: "")
    }
    
    func encode(_ value: Bool) throws { box(value, path: "")}
    func encode(_ value: String) throws { box(value, path: "")}
    func encode(_ value: Double) throws { box(value, path: "")}
    func encode(_ value: Float) throws { box(value, path: "")}
    func encode(_ value: Int) throws { box(value, path: "")}
    func encode(_ value: Int8) throws { box(value, path: "")}
    func encode(_ value: Int16) throws { box(value, path: "")}
    func encode(_ value: Int32) throws { box(value, path: "")}
    func encode(_ value: Int64) throws { box(value, path: "")}
    func encode(_ value: UInt) throws { box(value, path: "")}
    func encode(_ value: UInt8) throws { box(value, path: "")}
    func encode(_ value: UInt16) throws { box(value, path: "")}
    func encode(_ value: UInt32) throws { box(value, path: "")}
    func encode(_ value: UInt64) throws { box(value, path: "")}
    
    func encode<T: Encodable>(_ value: T) throws {
        try value.encode(to: self)
    }
    
    func singleValueContainer() -> SingleValueEncodingContainer {
        return self
    }
}

extension _QueryEncoder {
    /// Returns the given value boxed in a container appropriate for pushing onto the container stack.
    func box(_ value: Any, path: String) {
        if fullPath != "" && path != "" {
            self.result["\(fullPath).\(path)"] = value
        } else {
            self.result["\(fullPath)\(path)"] = value
        }
    }

    func box(_ value: Encodable) throws {
        // store previous container coding map to revert on function exit
        let prevContainerCodingOwner = self.containerCodingMapType
        defer { self.containerCodingMapType = prevContainerCodingOwner }
        // set the current container coding map
        let containerCodingMap = value as? XMLCodable
        containerCodingMapType = containerCodingMap != nil ? Swift.type(of:containerCodingMap!) : nil
        
        try value.encode(to: self)
    }
}

//===----------------------------------------------------------------------===//
// Shared Key Types
//===----------------------------------------------------------------------===//

fileprivate struct _QueryKey : CodingKey {
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
    
    fileprivate static let `super` = _QueryKey(stringValue: "super")!
}

