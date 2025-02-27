//===----------------------------------------------------------------------===//
//
// This source file is part of the Soto for AWS open source project
//
// Copyright (c) 2023 the Soto project authors
// Licensed under Apache License v2.0
//
// See LICENSE.txt for license information
// See CONTRIBUTORS.txt for the list of Soto project authors
//
// SPDX-License-Identifier: Apache-2.0
//
//===----------------------------------------------------------------------===//

/// Document value that can hold arbitrary data (See https://smithy.io/2.0/spec/simple-types.html#document)
public enum AWSDocument: Sendable, Codable, Equatable {
    case string(String)
    case double(Double)
    case integer(Int)
    case boolean(Bool)
    case array([AWSDocument])
    case map([String: AWSDocument])
    case null

    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let string = try? container.decode(String.self) {
            self = .string(string)
        } else if let integer = try? container.decode(Int.self) {
            self = .integer(integer)
        } else if let double = try? container.decode(Double.self) {
            self = .double(double)
        } else if let boolean = try? container.decode(Bool.self) {
            self = .boolean(boolean)
        } else if let array = try? container.decode([AWSDocument].self) {
            self = .array(array)
        } else if let map = try? container.decode([String: AWSDocument].self) {
            self = .map(map)
        } else if container.decodeNil() {
            self = .null
        } else {
            throw DecodingError.typeMismatch(AWSDocument.self, .init(codingPath: decoder.codingPath, debugDescription: "Failed to decode"))
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let value): try container.encode(value)
        case .integer(let value): try container.encode(value)
        case .double(let value): try container.encode(value)
        case .boolean(let value): try container.encode(value)
        case .array(let value): try container.encode(value)
        case .map(let value): try container.encode(value)
        case .null: try container.encodeNil()
        }
    }
}

extension AWSDocument: ExpressibleByStringLiteral {
    public init(stringLiteral value: StringLiteralType) {
        self = .string(value)
    }
}
extension AWSDocument: ExpressibleByIntegerLiteral {
    public init(integerLiteral value: IntegerLiteralType) {
        self = .integer(value)
    }
}
extension AWSDocument: ExpressibleByFloatLiteral {
    public init(floatLiteral value: FloatLiteralType) {
        self = .double(value)
    }
}
extension AWSDocument: ExpressibleByBooleanLiteral {
    public init(booleanLiteral value: BooleanLiteralType) {
        self = .boolean(value)
    }
}
extension AWSDocument: ExpressibleByArrayLiteral {
    public init(arrayLiteral values: AWSDocument...) {
        self = .array(values)
    }
}
extension AWSDocument: ExpressibleByDictionaryLiteral {
    public init(dictionaryLiteral values: (String, AWSDocument)...) {
        self = .map(.init(values) { first, _ in first })
    }
}
