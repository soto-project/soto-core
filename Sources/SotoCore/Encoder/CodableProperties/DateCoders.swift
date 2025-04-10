//===----------------------------------------------------------------------===//
//
// This source file is part of the Soto for AWS open source project
//
// Copyright (c) 2020-2022 the Soto project authors
// Licensed under Apache License v2.0
//
// See LICENSE.txt for license information
// See CONTRIBUTORS.txt for the list of Soto project authors
//
// SPDX-License-Identifier: Apache-2.0
//
//===----------------------------------------------------------------------===//

import struct Foundation.Date
import class Foundation.DateFormatter
import class Foundation.ISO8601DateFormatter
import struct Foundation.Locale
import struct Foundation.TimeZone

// MARK: TimeStamp Coders

/// Protocol for time stamp coders that use a DateFormatter. Use this to enforce the timestamp format we require, or to set the timestamp format output
public protocol DateFormatCoder: CustomDecoder, CustomEncoder where CodableValue == Date {
    /// format used by DateFormatter
    static var format: String { get }
    /// Date formatter
    static var dateFormatter: DateFormatter { get }
}

extension DateFormatCoder {
    /// decode Date using DateFormatter
    public static func decode(from decoder: Decoder) throws -> CodableValue {
        let container = try decoder.singleValueContainer()
        let value = try container.decode(String.self)
        if let date = dateFormatter.date(from: value) {
            return date
        }
        throw DecodingError.dataCorruptedError(in: container, debugDescription: "String is not the correct date format")
    }

    /// encode Date using DateFormatter
    public static func encode(value: CodableValue, to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(dateFormatter.string(from: value))
    }

    public static func string(from value: Date) -> String? {
        dateFormatter.string(from: value)
    }

    /// create DateFormatter
    static func createDateFormatter() -> DateFormatter {
        let dateFormatter = DateFormatter()
        dateFormatter.locale = Locale(identifier: "en_US_POSIX")
        dateFormatter.dateFormat = format
        dateFormatter.timeZone = TimeZone(secondsFromGMT: 0)
        return dateFormatter
    }
}

/// Date coder for ISO8601 format
public struct ISO8601DateCoder: CustomDecoder, CustomEncoder {
    public typealias CodableValue = Date
    /// decode Date using DateFormatter
    public static func decode(from decoder: Decoder) throws -> Date {
        let container = try decoder.singleValueContainer()
        let value = try container.decode(String.self)
        for dateFormatter in self.dateFormatters {
            if let date = dateFormatter.date(from: value) {
                return date
            }
        }
        throw DecodingError.dataCorruptedError(in: container, debugDescription: "String is not the correct date format")
    }

    /// encode Date using DateFormatter
    public static func encode(value: Date, to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(self.dateFormatters[0].string(from: value))
    }

    public static func string(from value: Date) -> String? {
        self.dateFormatters[0].string(from: value)
    }

    nonisolated(unsafe) static let dateFormatters: [ISO8601DateFormatter] = {
        let dateFormatters: [ISO8601DateFormatter] = [ISO8601DateFormatter(), ISO8601DateFormatter()]
        dateFormatters[0].formatOptions = [.withFullDate, .withFullTime, .withFractionalSeconds]
        dateFormatters[1].formatOptions = [.withFullDate, .withFullTime]
        return dateFormatters
    }()
}

/// Date coder for HTTP header format
public struct HTTPHeaderDateCoder: DateFormatCoder {
    public static let format = "EEE, d MMM yyy HH:mm:ss z"
    public static let dateFormatter = createDateFormatter()
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
