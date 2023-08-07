//===----------------------------------------------------------------------===//
//
// This source file is part of the Soto for AWS open source project
//
// Copyright (c) 2017-2022 the Soto project authors
// Licensed under Apache License v2.0
//
// See LICENSE.txt for license information
// See CONTRIBUTORS.txt for the list of Soto project authors
//
// SPDX-License-Identifier: Apache-2.0
//
//===----------------------------------------------------------------------===//

import var Foundation.NSNotFound
import struct Foundation.NSRange
import class Foundation.NSRegularExpression
import struct Foundation.UUID

/// Protocol for the input and output objects for all AWS service commands.
///
/// They need to be Codable so they can be serialized. They also need to provide details
/// on how their container classes are coded when serializing XML.
public protocol AWSShape: Sendable {
    static var _options: AWSShapeOptions { get }
}

extension AWSShape {
    public static var _options: AWSShapeOptions { .init() }
}

extension AWSShape {
    /// Return an idempotencyToken
    public static func idempotencyToken() -> String {
        return UUID().uuidString
    }
}

/// AWSShape that can be encoded into API input
public protocol AWSEncodableShape: AWSShape & Encodable {
    /// Return XML root name
    static var _xmlRootNodeName: String? { get }
    /// The XML namespace for the object
    static var _xmlNamespace: String? { get }

    /// returns if a shape is valid. The checks for validity are defined by the AWS model files we get from http://github.com/aws/aws-sdk-go
    func validate(name: String) throws
}

public extension AWSEncodableShape {
    /// Return XML root name
    static var _xmlRootNodeName: String? { return nil }
    /// The XML namespace for the object
    static var _xmlNamespace: String? { return nil }
}

/// Validation code to add to AWSEncodableShape
public extension AWSEncodableShape {
    func validate() throws {
        try validate(name: "\(type(of: self))")
    }

    /// stub validate function for all shapes
    func validate(name: String) throws {}

    /// Return validation error
    static func validationError(_ message: String) -> Error {
        return AWSClientError(.validationError, context: .init(message: message, responseCode: .badRequest))
    }

    func validate<T: BinaryInteger>(_ value: T, name: String, parent: String, min: T) throws {
        guard value >= min else { throw Self.validationError("\(parent).\(name) (\(value)) is less than minimum allowed value \(min).") }
    }

    func validate<T: BinaryInteger>(_ value: T, name: String, parent: String, max: T) throws {
        guard value <= max else { throw Self.validationError("\(parent).\(name) (\(value)) is greater than the maximum allowed value \(max).") }
    }

    func validate<T: FloatingPoint>(_ value: T, name: String, parent: String, min: T) throws {
        guard value >= min else { throw Self.validationError("\(parent).\(name) (\(value)) is less than minimum allowed value \(min).") }
    }

    func validate<T: FloatingPoint>(_ value: T, name: String, parent: String, max: T) throws {
        guard value <= max else { throw Self.validationError("\(parent).\(name) (\(value)) is greater than the maximum allowed value \(max).") }
    }

    func validate<T: Collection>(_ value: T, name: String, parent: String, min: Int) throws {
        guard value.count >= min else { throw Self.validationError("Length of \(parent).\(name) (\(value.count)) is less than minimum allowed value \(min).") }
    }

    func validate<T: Collection>(_ value: T, name: String, parent: String, max: Int) throws {
        guard value.count <= max else { throw Self.validationError("Length of \(parent).\(name) (\(value.count)) is greater than the maximum allowed value \(max).") }
    }

    func validate(_ value: AWSBase64Data, name: String, parent: String, min: Int) throws {
        guard value.base64count >= min else { throw Self.validationError("Length of \(parent).\(name) (\(value.base64count)) is less than minimum allowed value \(min).") }
    }

    func validate(_ value: AWSBase64Data, name: String, parent: String, max: Int) throws {
        guard value.base64count <= max else { throw Self.validationError("Length of \(parent).\(name) (\(value.base64count)) is greater than the maximum allowed value \(max).") }
    }

    func validate(_ value: AWSHTTPBody, name: String, parent: String, min: Int) throws {
        if let size = value.length {
            guard size >= min else {
                throw Self.validationError("Length of \(parent).\(name) (\(size)) is less than minimum allowed value \(min).")
            }
        }
    }

    func validate(_ value: AWSHTTPBody, name: String, parent: String, max: Int) throws {
        if let size = value.length {
            guard size <= max else {
                throw Self.validationError("Length of \(parent).\(name) (\(size)) is greater than the maximum allowed value \(max).")
            }
        }
    }

    func validate(_ value: String, name: String, parent: String, pattern: String) throws {
        let regularExpression = try NSRegularExpression(pattern: pattern, options: [])
        let nsRange = NSRange(value.startIndex..<value.endIndex, in: value)
        let firstMatch = regularExpression.rangeOfFirstMatch(in: value, options: .anchored, range: nsRange)
        guard firstMatch.location != NSNotFound, firstMatch.length > 0 else { throw Self.validationError("\(parent).\(name) (\(value)) does not match pattern \(pattern).") }
    }

    // validate optional values
    func validate<T: BinaryInteger>(_ value: T?, name: String, parent: String, min: T) throws {
        guard let value = value else { return }
        try validate(value, name: name, parent: parent, min: min)
    }

    func validate<T: BinaryInteger>(_ value: T?, name: String, parent: String, max: T) throws {
        guard let value = value else { return }
        try validate(value, name: name, parent: parent, max: max)
    }

    func validate<T: FloatingPoint>(_ value: T?, name: String, parent: String, min: T) throws {
        guard let value = value else { return }
        try validate(value, name: name, parent: parent, min: min)
    }

    func validate<T: FloatingPoint>(_ value: T?, name: String, parent: String, max: T) throws {
        guard let value = value else { return }
        try validate(value, name: name, parent: parent, max: max)
    }

    func validate<T: Collection>(_ value: T?, name: String, parent: String, min: Int) throws {
        guard let value = value else { return }
        try validate(value, name: name, parent: parent, min: min)
    }

    func validate<T: Collection>(_ value: T?, name: String, parent: String, max: Int) throws {
        guard let value = value else { return }
        try validate(value, name: name, parent: parent, max: max)
    }

    func validate(_ value: AWSBase64Data?, name: String, parent: String, min: Int) throws {
        guard let value = value else { return }
        try validate(value, name: name, parent: parent, min: min)
    }

    func validate(_ value: AWSBase64Data?, name: String, parent: String, max: Int) throws {
        guard let value = value else { return }
        try validate(value, name: name, parent: parent, max: max)
    }

    func validate(_ value: AWSHTTPBody?, name: String, parent: String, min: Int) throws {
        guard let value = value else { return }
        try validate(value, name: name, parent: parent, min: min)
    }

    func validate(_ value: AWSHTTPBody?, name: String, parent: String, max: Int) throws {
        guard let value = value else { return }
        try validate(value, name: name, parent: parent, max: max)
    }

    func validate(_ value: String?, name: String, parent: String, pattern: String) throws {
        guard let value = value else { return }
        try validate(value, name: name, parent: parent, pattern: pattern)
    }
}

/// AWSShape that can be decoded from API output
public protocol AWSDecodableShape: AWSShape & Decodable {}

/// AWSShape options.
public struct AWSShapeOptions: OptionSet {
    public var rawValue: Int

    public init(rawValue: Int) {
        self.rawValue = rawValue
    }

    /// Request payload can be streamed
    public static let allowStreaming = AWSShapeOptions(rawValue: 1 << 0)
    /// Request payload can be streamed using Transfer-Encoding: chunked
    public static let allowChunkedStreaming = AWSShapeOptions(rawValue: 1 << 1)
    /// Response Payload is raw data, or an event stream
    public static let rawPayload = AWSShapeOptions(rawValue: 1 << 2)
    /// Request can include a checksum header
    public static let checksumHeader = AWSShapeOptions(rawValue: 1 << 3)
    /// Checksum calculation of body is required
    public static let checksumRequired = AWSShapeOptions(rawValue: 1 << 4)
    /// Request includes a MD5 checksum
    public static let md5ChecksumHeader = AWSShapeOptions(rawValue: 1 << 5)
}
