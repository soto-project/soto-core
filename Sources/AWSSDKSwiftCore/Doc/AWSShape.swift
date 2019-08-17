//
//  AWSShape.swift
//  AWSSDKSwift
//
//  Created by Yuki Takei on 2017/04/12.
//
//

import Foundation

public protocol AWSShape: Codable, XMLContainerCodingMap {
    static var payloadPath: String? { get }
    static var _xmlNamespace: String? { get }
    static var _members: [AWSShapeMember] { get }
    
    func validate(name: String) throws
}

extension AWSShape {
    public static var payloadPath: String? {
        return nil
    }
    
    public static var _xmlNamespace: String? {
        return nil
    }
    
    public static var _members: [AWSShapeMember] {
        return []
    }
    
    public static func getMember(named: String) -> AWSShapeMember? {
        return _members.first {$0.label == named}
    }
    
    public static func getMember(locationNamed: String) -> AWSShapeMember? {
        return _members.first {
            if let location = $0.location {
                switch location {
                case .body(let name):
                    return name == locationNamed
                case .uri(let name):
                    return name == locationNamed
                case .header(let name):
                    return name == locationNamed
                case .querystring(let name):
                    return name == locationNamed
                }
            } else {
                return $0.label == locationNamed
            }
        }
    }
    
    public static var pathParams: [String: String] {
        var params: [String: String] = [:]
        for member in _members {
            guard let location = member.location else { continue }
            if case .uri(let name) = location {
                params[name] = member.label
            }
        }
        return params
    }
    
    public static var headerParams: [String: String] {
        var params: [String: String] = [:]
        for member in _members {
            guard let location = member.location else { continue }
            if case .header(let name) = location {
                params[name] = member.label
            }
        }
        return params
    }
    
    public static var queryParams: [String: String] {
        var params: [String: String] = [:]
        for member in _members {
            guard let location = member.location else { continue }
            if case .querystring(let name) = location {
                params[name] = member.label
            }
        }
        return params
    }
    
    public static var hasEncodableBody: Bool {
        for member in _members {
            if let location = member.location {
                if case .body(_) = location {
                    return true
                }
            } else {
                return true
            }
        }
        return false
    }
    
}

/// Validation code to add to AWSShape
extension AWSShape {
    public func validate() throws {
        try validate(name: "\(type(of:self))")
    }
    
    /// stub function for all shapes
    public func validate(name: String) throws {
    }
    
    public func validate<T : BinaryInteger>(_ value: T, name: String, parent: String, min: T) throws {
        guard value >= min else { throw AWSClientError.validationError(message: "\(parent).\(name) (\(value)) is less than minimum allowed value \(min).") }
    }
    public func validate<T : BinaryInteger>(_ value: T, name: String, parent: String, max: T) throws {
        guard value <= max else { throw AWSClientError.validationError(message: "\(parent).\(name) (\(value)) is greater than the maximum allowed value \(max).") }
    }
    public func validate<T : FloatingPoint>(_ value: T, name: String, parent: String, min: T) throws {
        guard value >= min else { throw AWSClientError.validationError(message: "\(parent).\(name) (\(value)) is less than minimum allowed value \(min).") }
    }
    public func validate<T : FloatingPoint>(_ value: T, name: String, parent: String, max: T) throws {
        guard value <= max else { throw AWSClientError.validationError(message: "\(parent).\(name) (\(value)) is greater than the maximum allowed value \(max).") }
    }
    public func validate<T : Collection>(_ value: T, name: String, parent: String, min: Int) throws {
        guard value.count >= min else { throw AWSClientError.validationError(message: "Length of \(parent).\(name) (\(value)) is less than minimum allowed value \(min).") }
    }
    public func validate<T : Collection>(_ value: T, name: String, parent: String, max: Int) throws {
        guard value.count <= max else { throw AWSClientError.validationError(message: "Length of \(parent).\(name) (\(value)) is greater than the maximum allowed value \(max).") }
    }
    public func validate(_ value: String, name: String, parent: String, pattern: String) throws {
        let regularExpression = try NSRegularExpression(pattern: pattern, options: [])
        let firstMatch = regularExpression.rangeOfFirstMatch(in: value, options: .anchored, range: NSMakeRange(0, value.count))
        guard firstMatch.location != NSNotFound && firstMatch.length == value.count else { throw AWSClientError.validationError(message: "\(parent).\(name) (\(value)) does not match pattern \(pattern).") }
    }
    // optional values
    public func validate<T : BinaryInteger>(_ value: T?, name: String, parent: String, min: T) throws {
        guard let value = value else {return}
        try validate(value, name: name, parent: parent, min: min)
    }
    public func validate<T : BinaryInteger>(_ value: T?, name: String, parent: String, max: T) throws {
        guard let value = value else {return}
        try validate(value, name: name, parent: parent, max: max)
    }
    public func validate<T : FloatingPoint>(_ value: T?, name: String, parent: String, min: T) throws {
        guard let value = value else {return}
        try validate(value, name: name, parent: parent, min: min)
    }
    public func validate<T : FloatingPoint>(_ value: T?, name: String, parent: String, max: T) throws {
        guard let value = value else {return}
        try validate(value, name: name, parent: parent, max: max)
    }
    public func validate<T : Collection>(_ value: T?, name: String, parent: String, min: Int) throws {
        guard let value = value else {return}
        try validate(value, name: name, parent: parent, min: min)
    }
    public func validate<T : Collection>(_ value: T?, name: String, parent: String, max: Int) throws {
        guard let value = value else {return}
        try validate(value, name: name, parent: parent, max: max)
    }
    public func validate(_ value: String?, name: String, parent: String, pattern: String) throws {
        guard let value = value else {return}
        try validate(value, name: name, parent: parent, pattern: pattern)
    }
}

extension AWSShape {
    public static func idempotencyToken() -> String {
        return UUID().uuidString
    }
}

/// extension to CollectionEncoding to produce the XML equivalent class
extension ShapeEncoding {
    public var xmlEncoding : XMLContainerCoding? {
        switch self {
        case .default:
            return nil
        case .flatList:
            return .default
        case .list(let entry):
            return .array(entry: entry)
        case .flatMap(let key, let value):
            return .dictionary(entry: nil, key: key, value: value)
        case .map(let entry, let key, let value):
            return .dictionary(entry: entry, key: key, value: value)
        }
    }
}

/// extension to AWSShape that returns XML container encoding for members of it
extension AWSShape {
    public static func getXMLContainerCoding(for key: CodingKey) -> XMLContainerCoding? {
        if let member = getMember(locationNamed: key.stringValue) {
            return member.shapeEncoding.xmlEncoding
        }
        return nil
    }
}
