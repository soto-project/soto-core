//===----------------------------------------------------------------------===//
//
// This source file is part of the Soto for AWS open source project
//
// Copyright (c) 2020 the Soto project authors
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
import struct Foundation.Locale
import struct Foundation.TimeZone

// MARK: TimeStamp Coders

/// Protocol for time stamp coders that use a DateFormatter. Use this to enforce the timestamp format we require, or to set the timestamp format output
protocol DateFormatCoder: CustomDecoder, CustomEncoder where CodableValue == Date {
    /// format used by DateFormatter
    static var formats: [String] { get }
    /// Date formatter
    static var dateFormatters: [DateFormatter] { get }
}

extension DateFormatCoder {
    /// decode Date using DateFormatter
    public static func decode(from decoder: Decoder) throws -> CodableValue {
        let container = try decoder.singleValueContainer()
        let value = try container.decode(String.self)
        for dateFormatter in dateFormatters {
            if let date = dateFormatter.date(from: value) {
                return date
            }
        }
        throw DecodingError.dataCorruptedError(in: container, debugDescription: "String is not the correct date format")
    }

    /// encode Date using DateFormatter
    public static func encode(value: CodableValue, to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(dateFormatters[0].string(from: value))
    }

    public static func string(from value: Date) -> String? {
        dateFormatters[0].string(from: value)
    }

    /// create DateFormatter
    static func createDateFormatters() -> [DateFormatter] {
        var dateFormatters: [DateFormatter] = []
        precondition(formats.count > 0, "TimeStampFormatterCoder requires at least one format")
        for format in formats {
            let dateFormatter = DateFormatter()
            dateFormatter.locale = Locale(identifier: "en_US_POSIX")
            dateFormatter.dateFormat = format
            dateFormatter.timeZone = TimeZone(secondsFromGMT: 0)
            dateFormatters.append(dateFormatter)
        }
        return dateFormatters
    }
}

/// Date coder for ISO8601 format
public struct ISO8601DateCoder: DateFormatCoder {
    public static let formats = ["yyyy-MM-dd'T'HH:mm:ss.SSS'Z'", "yyyy-MM-dd'T'HH:mm:ss'Z'"]
    public static let dateFormatters = createDateFormatters()
}

/// Date coder for HTTP header format
public struct HTTPHeaderDateCoder: DateFormatCoder {
    public static let formats = ["EEE, d MMM yyy HH:mm:ss z"]
    public static let dateFormatters = createDateFormatters()
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
}
