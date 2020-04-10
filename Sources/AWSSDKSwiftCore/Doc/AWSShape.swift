//===----------------------------------------------------------------------===//
//
// This source file is part of the AWSSDKSwift open source project
//
// Copyright (c) 2017-2020 the AWSSDKSwift project authors
// Licensed under Apache License v2.0
//
// See LICENSE.txt for license information
// See CONTRIBUTORS.txt for the list of AWSSDKSwift project authors
//
// SPDX-License-Identifier: Apache-2.0
//
//===----------------------------------------------------------------------===//

import struct Foundation.UUID
import class  Foundation.NSRegularExpression
import var    Foundation.NSNotFound
import func   Foundation.NSMakeRange

/// Protocol for the input and output objects for all AWS service commands. They need to be Codable so they can be serialized. They also need to provide details on how their container classes are coded when serializing XML.
public protocol AWSShape: XMLCodable {
    /// The array of members serialization helpers
    static var _encoding: [AWSMemberEncoding] { get }
}

extension AWSShape {
    public static var _encoding: [AWSMemberEncoding] {
        return []
    }

    /// return member with provided name
    public static func getEncoding(for: String) -> AWSMemberEncoding? {
        return _encoding.first {$0.label == `for`}
    }

    /// return list of member variables serialized in the URL path
    public static var pathParams: [String: String] {
        var params: [String: String] = [:]
        for member in _encoding {
            guard let location = member.location else { continue }
            if case .uri(let name) = location {
                params[name] = member.label
            }
        }
        return params
    }

    /// return list of member variables serialized in the headers
    public static var headerParams: [String: String] {
        var params: [String: String] = [:]
        for member in _encoding {
            guard let location = member.location else { continue }
            if case .header(let name) = location {
                params[name] = member.label
            }
        }
        return params
    }

    /// return list of member variables serialized as query parameters
    public static var queryParams: [String: String] {
        var params: [String: String] = [:]
        for member in _encoding {
            guard let location = member.location else { continue }
            if case .querystring(let name) = location {
                params[name] = member.label
            }
        }
        return params
    }
}

extension AWSShape {
    /// Return an idempotencyToken 
    public static func idempotencyToken() -> String {
        return UUID().uuidString
    }
}

/// extension to CollectionEncoding to produce the XML equivalent class
extension AWSMemberEncoding.ShapeEncoding {
    public var xmlEncoding : XMLContainerCoding? {
        switch self {
        case .default, .blob:
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
    /// return member for CodingKey
    public static func getEncoding(forKey: CodingKey) -> AWSMemberEncoding? {
        return _encoding.first {
            if let location = $0.location, case .body(let name) = location {
                return name == forKey.stringValue
            } else {
                return $0.label == forKey.stringValue
            }
        }
    }

    public static func getXMLContainerCoding(for key: CodingKey) -> XMLContainerCoding? {
        if let encoding = getEncoding(forKey: key) {
            return encoding.shapeEncoding.xmlEncoding
        }
        return nil
    }
}

/// AWSShape that can be encoded
public protocol AWSEncodableShape: AWSShape & Encodable {
    /// The XML namespace for the object
    static var _xmlNamespace: String? { get }
    
    /// returns if a shape is valid. The checks for validity are defined by the AWS model files we get from http://github.com/aws/aws-sdk-go
    func validate(name: String) throws
}

public extension AWSEncodableShape {
    static var _xmlNamespace: String? { return nil }
}

/// Validation code to add to AWSEncodableShape
public extension AWSEncodableShape {
    func validate() throws {
        try validate(name: "\(type(of:self))")
    }

    /// stub validate function for all shapes
    func validate(name: String) throws {
    }

    func validate<T : BinaryInteger>(_ value: T, name: String, parent: String, min: T) throws {
        guard value >= min else { throw AWSClientError.validationError(message: "\(parent).\(name) (\(value)) is less than minimum allowed value \(min).") }
    }
    func validate<T : BinaryInteger>(_ value: T, name: String, parent: String, max: T) throws {
        guard value <= max else { throw AWSClientError.validationError(message: "\(parent).\(name) (\(value)) is greater than the maximum allowed value \(max).") }
    }
    func validate<T : FloatingPoint>(_ value: T, name: String, parent: String, min: T) throws {
        guard value >= min else { throw AWSClientError.validationError(message: "\(parent).\(name) (\(value)) is less than minimum allowed value \(min).") }
    }
    func validate<T : FloatingPoint>(_ value: T, name: String, parent: String, max: T) throws {
        guard value <= max else { throw AWSClientError.validationError(message: "\(parent).\(name) (\(value)) is greater than the maximum allowed value \(max).") }
    }
    func validate<T : Collection>(_ value: T, name: String, parent: String, min: Int) throws {
        guard value.count >= min else { throw AWSClientError.validationError(message: "Length of \(parent).\(name) (\(value.count)) is less than minimum allowed value \(min).") }
    }
    func validate<T : Collection>(_ value: T, name: String, parent: String, max: Int) throws {
        guard value.count <= max else { throw AWSClientError.validationError(message: "Length of \(parent).\(name) (\(value.count)) is greater than the maximum allowed value \(max).") }
    }
    func validate(_ value: String, name: String, parent: String, pattern: String) throws {
        let regularExpression = try NSRegularExpression(pattern: pattern, options: [])
        let firstMatch = regularExpression.rangeOfFirstMatch(in: value, options: .anchored, range: NSMakeRange(0, value.count))
        guard firstMatch.location != NSNotFound && firstMatch.length > 0 else { throw AWSClientError.validationError(message: "\(parent).\(name) (\(value)) does not match pattern \(pattern).") }
    }
    // validate optional values
    func validate<T : BinaryInteger>(_ value: T?, name: String, parent: String, min: T) throws {
        guard let value = value else {return}
        try validate(value, name: name, parent: parent, min: min)
    }
    func validate<T : BinaryInteger>(_ value: T?, name: String, parent: String, max: T) throws {
        guard let value = value else {return}
        try validate(value, name: name, parent: parent, max: max)
    }
    func validate<T : FloatingPoint>(_ value: T?, name: String, parent: String, min: T) throws {
        guard let value = value else {return}
        try validate(value, name: name, parent: parent, min: min)
    }
    func validate<T : FloatingPoint>(_ value: T?, name: String, parent: String, max: T) throws {
        guard let value = value else {return}
        try validate(value, name: name, parent: parent, max: max)
    }
    func validate<T : Collection>(_ value: T?, name: String, parent: String, min: Int) throws {
        guard let value = value else {return}
        try validate(value, name: name, parent: parent, min: min)
    }
    func validate<T : Collection>(_ value: T?, name: String, parent: String, max: Int) throws {
        guard let value = value else {return}
        try validate(value, name: name, parent: parent, max: max)
    }
    func validate(_ value: String?, name: String, parent: String, pattern: String) throws {
        guard let value = value else {return}
        try validate(value, name: name, parent: parent, pattern: pattern)
    }
}

/// AWSShape that can be decoded
public protocol AWSDecodableShape: AWSShape & Decodable {}

/// Root AWSShape which include a payload
public protocol AWSShapeWithPayload {
    /// The path to the object that is included in the request body
    static var payloadPath: String? { get }
}

public extension AWSShapeWithPayload {
    static var payloadPath: String? {
        return nil
    }
}
