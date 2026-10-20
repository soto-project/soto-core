//===----------------------------------------------------------------------===//
//
// This source file is part of the Soto for AWS open source project
//
// Copyright (c) 2020-2026 the Soto project authors
// Licensed under Apache License v2.0
//
// See LICENSE.txt for license information
// See CONTRIBUTORS.txt for the list of Soto project authors
//
// SPDX-License-Identifier: Apache-2.0
//
//===----------------------------------------------------------------------===//

// TODO: FoundationEssentials (DateFormatter)
#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif

// MARK: TimeStamp Coders

/// Date coder for ISO8601 format
public struct ISO8601DateCoder: CustomDecoder, CustomEncoder {
    public typealias CodableValue = Date

    public static func decode(from decoder: Decoder) throws -> CodableValue {
        let container = try decoder.singleValueContainer()
        let value = try container.decode(String.self)
        guard let date = Date(iso8601: value) else {
            throw DecodingError.typeMismatch(Date.self, .init(codingPath: decoder.codingPath, debugDescription: "Invalid Date string"))
        }
        return date
    }

    public static func encode(value: CodableValue, to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(value.iso8601)
    }

    public static func string(from value: Date) -> String? {
        value.iso8601
    }
}

/// Date coder for ISO8601 format
public struct HTTPHeaderDateCoder: CustomDecoder, CustomEncoder {
    public typealias CodableValue = Date

    public static func decode(from decoder: Decoder) throws -> CodableValue {
        let container = try decoder.singleValueContainer()
        let value = try container.decode(String.self)
        guard let date = Date(httpHeader: value) else {
            throw DecodingError.typeMismatch(Date.self, .init(codingPath: decoder.codingPath, debugDescription: "Invalid Date string"))
        }
        return date
    }

    public static func encode(value: CodableValue, to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(value.httpHeader)
    }

    public static func string(from value: Date) -> String? {
        value.httpHeader
    }
}

/// Unix Epoch Date coder
public struct UnixEpochDateCoder: CustomDecoder, CustomEncoder {
    public typealias CodableValue = Date

    public static func decode(from decoder: Decoder) throws -> CodableValue {
        let container = try decoder.singleValueContainer()
        let value = try container.decode(Double.self)
        return Date(timeIntervalSince1970: value)
    }

    public static func encode(value: CodableValue, to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(value.timeIntervalSince1970)
    }

    public static func string(from value: Date) -> String? {
        Int(value.timeIntervalSince1970).description
    }
}
