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
        var container = try decoder.singleValueContainer()
        if let string = container.decode(String.self) {
            self = .string(string)
        } else if let integer = container.decode(Int.self) {
            self = .integer(integer)
        } else if let double = container.decode(Double.self) {
            self = .double(double)
        } else if let boolean = container.decode(Bool.self) {
            self = .boolean(boolean)
        } else if let array = container.decode([AWSDocument].self) {
            self = .array(array)
        } else if let map = container.decode([String: AWSDocument].self) {
            self = .map(map)
        } else if let map = container.decodeNil() {
            self = .null
        } else {
            throw DecodingError.typeMismatch(AWSDocument.self, "Failed to decode")
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = try encoder.singleValueContainer()
        switch self {
        case .string(let value): container.encode(value)
        case .integer(let value): container.encode(value)
        case .double(let value): container.encode(value)
        case .boolean(let value): container.encode(value)
        case .array(let value): container.encode(value)
        case .dictionary(let value): container.encode(value)
        case .null: container.encodeNil()
        }
    }
}
