//
//  XMLDecoder.swift
//  AWSSDKSwift
//
//  Created by Adam Fowler on 2019/05/01.
//
//
import Foundation

public class AWSXMLEncoder {
    
    /// The strategy to use for encoding `Date` values.
    public enum DateEncodingStrategy {
        /// Defer to `Date` for choosing an encoding. This is the default strategy.
        case deferredToDate
        
        /// Encode the `Date` as a UNIX timestamp (as a JSON number).
        case secondsSince1970
        
        /// Encode the `Date` as UNIX millisecond timestamp (as a JSON number).
        case millisecondsSince1970
        
        /// Encode the `Date` as an ISO-8601-formatted string (in RFC 3339 format).
        @available(macOS 10.12, iOS 10.0, watchOS 3.0, tvOS 10.0, *)
        case iso8601
        
        /// Encode the `Date` as a string formatted by the given formatter.
        case formatted(DateFormatter)
        
        /// Encode the `Date` as a custom value encoded by the given closure.
        ///
        /// If the closure fails to encode a value into the given encoder, the encoder will encode an empty automatic container in its place.
        case custom((Date, Encoder) throws -> Void)
    }
    
    /// The strategy to use for encoding `Data` values.
    public enum DataEncodingStrategy {
        /// Defer to `Data` for choosing an encoding.
        case deferredToData
        
        /// Encoded the `Data` as a Base64-encoded string. This is the default strategy.
        case base64
        
        /// Encode the `Data` as a custom value encoded by the given closure.
        ///
        /// If the closure fails to encode a value into the given encoder, the encoder will encode an empty automatic container in its place.
        case custom((Data, Encoder) throws -> Void)
    }
    
    /// The strategy to use for non-JSON-conforming floating-point values (IEEE 754 infinity and NaN).
    public enum NonConformingFloatEncodingStrategy {
        /// Throw upon encountering non-conforming values. This is the default strategy.
        case `throw`
        
        /// Encode the values using the given representation strings.
        case convertToString(positiveInfinity: String, negativeInfinity: String, nan: String)
    }
    
    /// The strategy to use in encoding dates. Defaults to `.deferredToDate`.
    open var dateEncodingStrategy: DateEncodingStrategy = .deferredToDate
    
    /// The strategy to use in encoding binary data. Defaults to `.base64`.
    open var dataEncodingStrategy: DataEncodingStrategy = .base64
    
    /// The strategy to use in encoding non-conforming numbers. Defaults to `.throw`.
    open var nonConformingFloatEncodingStrategy: NonConformingFloatEncodingStrategy = .throw
    
    /// Contextual user-provided information for use during encoding.
    open var userInfo: [CodingUserInfoKey : Any] = [:]
    
    /// Options set on the top-level encoder to pass down the encoding hierarchy.
    fileprivate struct _Options {
        let dateEncodingStrategy: DateEncodingStrategy
        let dataEncodingStrategy: DataEncodingStrategy
        let nonConformingFloatEncodingStrategy: NonConformingFloatEncodingStrategy
        let userInfo: [CodingUserInfoKey : Any]
    }
    
    /// The options set on the top-level encoder.
    fileprivate var options: _Options {
        return _Options(dateEncodingStrategy: dateEncodingStrategy,
                        dataEncodingStrategy: dataEncodingStrategy,
                        nonConformingFloatEncodingStrategy: nonConformingFloatEncodingStrategy,
                        userInfo: userInfo)
    }
    
    public init() {}
    
    open func encode<T : Encodable>(_ value: T, name: String? = nil) throws -> XMLElement {
        let rootName = name ?? "\(type(of: value))"
        let encoder = _AWSXMLEncoder(options: options, codingPath: [_XMLKey(stringValue: rootName, intValue: nil)])
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
    @discardableResult mutating func popContainer() -> XMLElement { return containers.removeLast() }
}

class _AWSXMLEncoder : Encoder {
    // MARK: Properties
    
    /// the encoder's storage
    var storage : _AWSXMLEncoderStorage

    /// Options set on the top-level encoder.
    fileprivate let options: AWSXMLEncoder._Options
    
    /// the path to the current point in encoding
    var codingPath: [CodingKey]
    
    /// contextual user-provided information for use during encoding
    var userInfo: [CodingUserInfoKey : Any] = [:]
    
    /// the top level key
    var currentKey : String { return codingPath.last!.stringValue }
    
    /// the top level xml element
    var element : XMLElement? { return storage.topContainer }

    // MARK: - Initialization
    fileprivate init(options: AWSXMLEncoder._Options, codingPath: [CodingKey] = []) {
        self.storage = _AWSXMLEncoderStorage()
        self.options = options
        self.codingPath = codingPath
    }
    
    // MARK: - Encoder methods
    
    func container<Key>(keyedBy type: Key.Type) -> KeyedEncodingContainer<Key> where Key : CodingKey {
        let newElement = XMLElement(name: currentKey)
        storage.topContainer?.addChild(newElement)
        storage.push(container: newElement)
        return KeyedEncodingContainer(KEC(newElement, referencing:self))
    }
    
    struct KEC<Key: CodingKey> : KeyedEncodingContainerProtocol {
        let encoder : _AWSXMLEncoder
        let element : XMLElement
        var codingPath: [CodingKey] { return encoder.codingPath }
        
        init(_ element : XMLElement, referencing encoder: _AWSXMLEncoder) {
            self.encoder = encoder
            self.element = element
        }
        
        func encodeNil(forKey key: Key) throws {
        }
        
        func encode(_ value: Bool, forKey key: Key) throws {
            let childElement = XMLElement(name: key.stringValue, stringValue: encoder.box(value))
            element.addChild(childElement)
        }
        
        func encode(_ value: String, forKey key: Key) throws {
            let childElement = XMLElement(name: key.stringValue, stringValue: encoder.box(value))
            element.addChild(childElement)
        }
        
        func encode(_ value: Int, forKey key: Key) throws {
            let childElement = XMLElement(name: key.stringValue, stringValue: encoder.box(value))
            element.addChild(childElement)
        }
        
        func encode(_ value: Int8, forKey key: Key) throws {
            let childElement = XMLElement(name: key.stringValue, stringValue: encoder.box(value))
            element.addChild(childElement)
        }
        
        func encode(_ value: Int16, forKey key: Key) throws {
            let childElement = XMLElement(name: key.stringValue, stringValue: encoder.box(value))
            element.addChild(childElement)
        }
        
        func encode(_ value: Int32, forKey key: Key) throws {
            let childElement = XMLElement(name: key.stringValue, stringValue: encoder.box(value))
            element.addChild(childElement)
        }
        
        func encode(_ value: Int64, forKey key: Key) throws {
            let childElement = XMLElement(name: key.stringValue, stringValue: encoder.box(value))
            element.addChild(childElement)
        }
        
        func encode(_ value: UInt, forKey key: Key) throws {
            let childElement = XMLElement(name: key.stringValue, stringValue: encoder.box(value))
            element.addChild(childElement)
        }
        
        func encode(_ value: UInt8, forKey key: Key) throws {
            let childElement = XMLElement(name: key.stringValue, stringValue: encoder.box(value))
            element.addChild(childElement)
        }
        
        func encode(_ value: UInt16, forKey key: Key) throws {
            let childElement = XMLElement(name: key.stringValue, stringValue: encoder.box(value))
            element.addChild(childElement)
        }
        
        func encode(_ value: UInt32, forKey key: Key) throws {
            let childElement = XMLElement(name: key.stringValue, stringValue: encoder.box(value))
            element.addChild(childElement)
        }
        
        func encode(_ value: UInt64, forKey key: Key) throws {
            let childElement = XMLElement(name: key.stringValue, stringValue: encoder.box(value))
            element.addChild(childElement)
        }
        
        func encode(_ value: Double, forKey key: Key) throws {
            let childElement = try XMLElement(name: key.stringValue, stringValue: encoder.box(value))
            element.addChild(childElement)
        }
        
        func encode(_ value: Float, forKey key: Key) throws {
            let childElement = try XMLElement(name: key.stringValue, stringValue: encoder.box(value))
            element.addChild(childElement)
        }
        
        func encode<T>(_ value: T, forKey key: Key) throws where T : Encodable {
            self.encoder.codingPath.append(key)
            defer { self.encoder.codingPath.removeLast() }
            try encoder.box(value)
       }
        
        func nestedContainer<NestedKey>(keyedBy keyType: NestedKey.Type, forKey key: Key) -> KeyedEncodingContainer<NestedKey> where NestedKey : CodingKey {
            self.encoder.codingPath.append(key)
            defer { self.encoder.codingPath.removeLast() }

            let newElement = XMLElement(name: key.stringValue)
            encoder.storage.topContainer?.addChild(newElement)
            encoder.storage.push(container: newElement)

            let container = KEC<NestedKey>(newElement, referencing: self.encoder)
            return KeyedEncodingContainer(container)
        }
        
        func nestedUnkeyedContainer(forKey key: Key) -> UnkeyedEncodingContainer {
            self.encoder.codingPath.append(key)
            defer { self.encoder.codingPath.removeLast() }
            
            let newElement = XMLElement(name: key.stringValue)
            encoder.storage.topContainer?.addChild(newElement)
            encoder.storage.push(container: newElement)
            
            return UKEC(newElement, referencing: self.encoder)
        }
        
        func superEncoder() -> Encoder {
            return _AWSXMLReferencingEncoder(referencing: encoder, key: _XMLKey.super, wrapping: element)
        }
        
        func superEncoder(forKey key: Key) -> Encoder {
            return _AWSXMLReferencingEncoder(referencing: encoder, key: key, wrapping: element)
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
            let childElement = XMLElement(name: encoder.currentKey, stringValue: encoder.box(value))
            element.addChild(childElement)
        }
        
        func encodeNil() throws {
        }
        
        func encode(_ value: String) throws {
            let childElement = XMLElement(name: encoder.currentKey, stringValue: encoder.box(value))
            element.addChild(childElement)
        }
        
        func encode(_ value: Int) throws {
            let childElement = XMLElement(name: encoder.currentKey, stringValue: encoder.box(value))
            element.addChild(childElement)
        }
        
        func encode(_ value: Int8) throws {
            let childElement = XMLElement(name: encoder.currentKey, stringValue: encoder.box(value))
            element.addChild(childElement)
        }
        
        func encode(_ value: Int16) throws {
            let childElement = XMLElement(name: encoder.currentKey, stringValue: encoder.box(value))
            element.addChild(childElement)
        }
        
        func encode(_ value: Int32) throws {
            let childElement = XMLElement(name: encoder.currentKey, stringValue: encoder.box(value))
            element.addChild(childElement)

        }
        
        func encode(_ value: Int64) throws {
            let childElement = XMLElement(name: encoder.currentKey, stringValue: encoder.box(value))
            element.addChild(childElement)
        }
        
        func encode(_ value: UInt) throws {
            let childElement = XMLElement(name: encoder.currentKey, stringValue: encoder.box(value))
            element.addChild(childElement)
        }
        
        func encode(_ value: UInt8) throws {
            let childElement = XMLElement(name: encoder.currentKey, stringValue: encoder.box(value))
            element.addChild(childElement)
        }
        
        func encode(_ value: UInt16) throws {
            let childElement = XMLElement(name: encoder.currentKey, stringValue: encoder.box(value))
            element.addChild(childElement)
        }
        
        func encode(_ value: UInt32) throws {
            let childElement = XMLElement(name: encoder.currentKey, stringValue: encoder.box(value))
            element.addChild(childElement)
        }
        
        func encode(_ value: UInt64) throws {
            let childElement = XMLElement(name: encoder.currentKey, stringValue: encoder.box(value))
            element.addChild(childElement)
        }
        
        func encode(_ value: Double) throws {
            let childElement = XMLElement(name: encoder.currentKey, stringValue: try encoder.box(value))
            element.addChild(childElement)
        }
        
        func encode(_ value: Float) throws {
            let childElement = XMLElement(name: encoder.currentKey, stringValue: try encoder.box(value))
            element.addChild(childElement)
            
        }
        
        func encode<T>(_ value: T) throws where T : Encodable {
            try encoder.box(value)
        }
        
        func nestedContainer<NestedKey>(keyedBy keyType: NestedKey.Type) -> KeyedEncodingContainer<NestedKey> where NestedKey : CodingKey {
            let newElement = XMLElement(name: encoder.currentKey)
            encoder.storage.topContainer?.addChild(newElement)
            encoder.storage.push(container: newElement)
            
            let container = KEC<NestedKey>(newElement, referencing: self.encoder)
            return KeyedEncodingContainer(container)
        }
        
        func nestedUnkeyedContainer() -> UnkeyedEncodingContainer {
            let newElement = XMLElement(name: encoder.currentKey)
            encoder.storage.topContainer?.addChild(newElement)
            encoder.storage.push(container: newElement)
            
            return UKEC(newElement, referencing: self.encoder)
        }
        
        func superEncoder() -> Encoder {
            return _AWSXMLReferencingEncoder(referencing: encoder, key: _XMLKey.super, wrapping: element)
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
        let childNode = XMLElement(name: currentKey, stringValue: box(value))
        element?.addChild(childNode)
    }
    
    func encode(_ value: String) throws {
        let childNode = XMLElement(name: currentKey, stringValue: box(value))
        element?.addChild(childNode)
    }
    
    func encode(_ value: Int) throws {
        let childNode = XMLElement(name: currentKey, stringValue: box(value))
        element?.addChild(childNode)
    }
    
    func encode(_ value: Int8) throws {
        let childNode = XMLElement(name: currentKey, stringValue: box(value))
        element?.addChild(childNode)
    }
    
    func encode(_ value: Int16) throws {
        let childNode = XMLElement(name: currentKey, stringValue: box(value))
        element?.addChild(childNode)
    }
    
    func encode(_ value: Int32) throws {
        let childNode = XMLElement(name: currentKey, stringValue: box(value))
        element?.addChild(childNode)
    }
    
    func encode(_ value: Int64) throws {
        let childNode = XMLElement(name: currentKey, stringValue: box(value))
        element?.addChild(childNode)
    }
    
    func encode(_ value: UInt) throws {
        let childNode = XMLElement(name: currentKey, stringValue: box(value))
        element?.addChild(childNode)
    }
    
    func encode(_ value: UInt8) throws {
        let childNode = XMLElement(name: currentKey, stringValue: box(value))
        element?.addChild(childNode)
    }
    
    func encode(_ value: UInt16) throws {
        let childNode = XMLElement(name: currentKey, stringValue: box(value))
        element?.addChild(childNode)
    }
    
    func encode(_ value: UInt32) throws {
        let childNode = XMLElement(name: currentKey, stringValue: box(value))
        element?.addChild(childNode)
    }
    
    func encode(_ value: UInt64) throws {
        let childNode = XMLElement(name: currentKey, stringValue: box(value))
        element?.addChild(childNode)
    }
    
    func encode(_ value: Double) throws {
        let childNode = XMLElement(name: currentKey, stringValue: try box(value))
        element?.addChild(childNode)
    }
    
    func encode(_ value: Float) throws {
        let childNode = XMLElement(name: currentKey, stringValue: try box(value))
        element?.addChild(childNode)
    }
    
    func encode<T>(_ value: T) throws where T : Encodable {
        try box(value)
    }
}

extension _AWSXMLEncoder {
    /// Returns the given value boxed in a container appropriate for pushing onto the container stack.
    fileprivate func box(_ value: Bool)   -> String { return value.description }
    fileprivate func box(_ value: Int)    -> String { return NSNumber(value: value).description }
    fileprivate func box(_ value: Int8)   -> String { return NSNumber(value: value).description }
    fileprivate func box(_ value: Int16)  -> String { return NSNumber(value: value).description }
    fileprivate func box(_ value: Int32)  -> String { return NSNumber(value: value).description }
    fileprivate func box(_ value: Int64)  -> String { return NSNumber(value: value).description }
    fileprivate func box(_ value: UInt)   -> String { return NSNumber(value: value).description }
    fileprivate func box(_ value: UInt8)  -> String { return NSNumber(value: value).description }
    fileprivate func box(_ value: UInt16) -> String { return NSNumber(value: value).description }
    fileprivate func box(_ value: UInt32) -> String { return NSNumber(value: value).description }
    fileprivate func box(_ value: UInt64) -> String { return NSNumber(value: value).description }
    fileprivate func box(_ value: String) -> String { return value }
    
    fileprivate func box(_ float: Float) throws -> String {
        guard !float.isInfinite && !float.isNaN else {
            guard case let .convertToString(positiveInfinity: posInfString,
                                            negativeInfinity: negInfString,
                                            nan: nanString) = self.options.nonConformingFloatEncodingStrategy else {
                                                throw EncodingError._invalidFloatingPointValue(float, at: codingPath)
            }
            
            if float == Float.infinity {
                return posInfString
            } else if float == -Float.infinity {
                return negInfString
            } else {
                return nanString
            }
        }
        
        return NSNumber(value: float).description
    }
    
    fileprivate func box(_ double: Double) throws -> String {
        guard !double.isInfinite && !double.isNaN else {
            guard case let .convertToString(positiveInfinity: posInfString,
                                            negativeInfinity: negInfString,
                                            nan: nanString) = self.options.nonConformingFloatEncodingStrategy else {
                                                throw EncodingError._invalidFloatingPointValue(double, at: codingPath)
            }
            
            if double == Double.infinity {
                return posInfString
            } else if double == -Double.infinity {
                return negInfString
            } else {
                return nanString
            }
        }
        
        return NSNumber(value: double).description
    }
    

    func box(_ date: Date) throws {
        switch self.options.dateEncodingStrategy {
        case .deferredToDate:
            // Must be called with a surrounding with(pushedKey:) call.
            // Dates encode as single-value objects; this can't both throw and push a container, so no need to catch the error.
            try date.encode(to: self)
            storage.popContainer()
            
        case .secondsSince1970:
            let node = XMLElement(name:currentKey, stringValue: date.timeIntervalSince1970.description)
            element?.addChild(node)
            
        case .millisecondsSince1970:
            let node = XMLElement(name:currentKey, stringValue: (1000.0 * date.timeIntervalSince1970).description)
            element?.addChild(node)
            
        case .iso8601:
            if #available(macOS 10.12, iOS 10.0, watchOS 3.0, tvOS 10.0, *) {
                let node = XMLElement(name:currentKey, stringValue:_iso8601Formatter.string(from: date))
                element?.addChild(node)
            } else {
                fatalError("ISO8601DateFormatter is unavailable on this platform.")
            }
            
        case .formatted(let formatter):
            let node = XMLElement(name:currentKey, stringValue:formatter.string(from: date))
            element?.addChild(node)
            
        case .custom(let closure):
            try closure(date, self)
        }
    }
    
    func box(_ data: Data) throws {
        switch self.options.dataEncodingStrategy {
        case .deferredToData:
            try data.encode(to: self)
            storage.popContainer()
            
        case .base64:
            let node = XMLElement(name:currentKey, stringValue: data.base64EncodedString())
            element?.addChild(node)
            
        case .custom(let closure):
            try closure(data, self)
        }
    }
    
    func box(_ url: URL) throws {
        let node = XMLElement(name:currentKey, stringValue: url.absoluteString)
        element?.addChild(node)
    }
    
    func box(_ value: Encodable) throws {
        let type = Swift.type(of: value)
        if type == Date.self || type == NSDate.self {
            return try self.box((value as! Date))
        } else if type == Data.self || type == NSData.self {
            return try self.box((value as! Data))
        } else if type == URL.self || type == NSURL.self {
            return try self.box((value as! URL))
        } else {
            try value.encode(to: self)
            storage.popContainer()
        }
    }
}

// MARK: - _AWSXMLReferencingEncoder

/// _AWSXMLReferencingEncoder is a special subclass of _AWSXMLEncoder which has its own storage, but references the contents of a different encoder.
/// It's used in superEncoder(), which returns a new encoder for encoding a superclass -- the lifetime of the encoder should not escape the scope it's created in, but it doesn't necessarily know when it's done being used (to write to the original container).
fileprivate class _AWSXMLReferencingEncoder : _AWSXMLEncoder {

    // MARK: - Properties
    
    /// The encoder we're referencing.
    fileprivate let encoder: _AWSXMLEncoder
    
    /// The container reference itself.
    private let reference: XMLElement
    
    // MARK: - Initialization
    
    /// Initializes `self` by referencing the given array container in the given encoder.
    fileprivate init(referencing encoder: _AWSXMLEncoder, key: CodingKey, wrapping element: XMLElement) {
        self.encoder = encoder
        self.reference = element
        super.init(options: encoder.options, codingPath: encoder.codingPath)
        
        self.codingPath.append(key)
    }
    
    // MARK: - Coding Path Operations
    
    // MARK: - Deinitialization
    
    // Finalizes `self` by writing the contents of our storage to the referenced encoder's storage.
    deinit {
        if let element = element {
            reference.addChild(element)
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

