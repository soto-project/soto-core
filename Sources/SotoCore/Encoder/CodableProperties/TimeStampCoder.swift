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
public protocol TimeStampFormatterCoder: CustomDecoder, CustomEncoder where CodableValue == TimeStamp {
    /// format used by DateFormatter
    static var format: String { get }
    /// Date formatter
    static var dateFormatter: DateFormatter { get }
}

extension TimeStampFormatterCoder {
    /// decode Date using DateFormatter
    public static func decode(from decoder: Decoder) throws -> CodableValue {
        let container = try decoder.singleValueContainer()
        let value = try container.decode(String.self)
        guard let date = Self.dateFormatter.date(from: value) else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "String is not the correct format for an ISO 8601 date")
        }
        return TimeStamp(date)
    }

    /// encode Date using DateFormatter
    public static func encode(value: CodableValue, to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(dateFormatter.string(from: value.dateValue))
    }

    /// create DateFormatter
    static func createDateFormatter() -> DateFormatter {
        let dateFormatter = DateFormatter()
        dateFormatter.locale = Locale(identifier: "en_US_POSIX")
        dateFormatter.dateFormat = Self.format
        dateFormatter.timeZone = TimeZone(secondsFromGMT: 0)
        return dateFormatter
    }
}

/// Date coder for ISO8601 format
public struct ISO8601TimeStampCoder: TimeStampFormatterCoder {
    public static let format = "yyyy-MM-dd'T'HH:mm:ss.SSS'Z'"
    public static let dateFormatter = createDateFormatter()
}

/// Date coder for HTTP header format
public struct HTTPHeaderTimeStampCoder: TimeStampFormatterCoder {
    public static let format = "EEE, d MMM yyy HH:mm:ss z"
    public static let dateFormatter = createDateFormatter()
}

/// Unix Epoch Date coder
public struct UnixEpochTimeStampCoder: CustomDecoder, CustomEncoder {
    public typealias CodableValue = TimeStamp

    public static func decode(from decoder: Decoder) throws -> CodableValue {
        let container = try decoder.singleValueContainer()
        let value = try container.decode(Double.self)
        return TimeStamp(value)
    }

    public static func encode(value: CodableValue, to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(value.dateValue.timeIntervalSince1970)
    }
}
