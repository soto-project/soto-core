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

import class  Foundation.DateFormatter
import struct Foundation.Locale
import struct Foundation.Date
import struct Foundation.TimeZone

/// Time stamp object that can encoded to ISO8601 format and decoded from ISO8601, HTTP date format and UNIX epoch seconds
public struct TimeStamp {
    
    public var stringValue: String {
        return TimeStamp.string(from:dateValue)
    }
    
    public let dateValue: Date

    public init(_ date: Date) {
        dateValue = date
    }
    
    public init?(_ string: String) {
        guard let date = TimeStamp.date(from: string) else { return nil }
        self.dateValue = date
    }
    
    public init(_ double: Double) {
        self.dateValue = Date(timeIntervalSince1970: double)
    }
    
    static func string(from date: Date) -> String {
        return defaultDateFormatter.string(from: date)
    }

    static func date(from string: String) -> Date? {
        for formatter in dateFormatters {
            if let date = formatter.date(from: string) {
                return date
            }
        }
        return nil
    }
    
    /// date formatter for outputting dates
    private static let defaultDateFormatter : DateFormatter = createDefaultDateFormatter()

    static func createDefaultDateFormatter() -> DateFormatter {
        let dateFormatter = DateFormatter()
        dateFormatter.locale = Locale(identifier: "en_US_POSIX")
        dateFormatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSS'Z'"
        dateFormatter.timeZone = TimeZone(secondsFromGMT: 0)
        return dateFormatter
    }

    /// date formatters for parsing date strings. Currently know of three different formats returned by AWS: iso, shorter iso and http
    static func createDateFormatters() -> [DateFormatter] {
        var dateFormatters : [DateFormatter] = [defaultDateFormatter]
        
        let shorterDateFormatter = DateFormatter()
        shorterDateFormatter.locale = Locale(identifier: "en_US_POSIX")
        shorterDateFormatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss'Z'"
        shorterDateFormatter.timeZone = TimeZone(secondsFromGMT: 0)
        dateFormatters.append(shorterDateFormatter)

        let httpDateFormatter = DateFormatter()
        httpDateFormatter.locale = Locale(identifier: "en_US_POSIX")
        httpDateFormatter.dateFormat = "EEE, d MMM yyy HH:mm:ss z"
        httpDateFormatter.timeZone = TimeZone(secondsFromGMT: 0)
        dateFormatters.append(httpDateFormatter)

        return dateFormatters
    }
    
    static var dateFormatters : [DateFormatter] = TimeStamp.createDateFormatters()
}


extension TimeStamp: Codable {
    
    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let value = try? container.decode(Double.self) {
            self.init(value)
        } else if let value = try? container.decode(String.self), let date = TimeStamp.date(from: value) {
            self.init(date)
        } else if let date = try? container.decode(Date.self) {
            self.init(date)
        } else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Expected string when decoding a Date")
        }
    }
    
    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(stringValue)
    }
}

