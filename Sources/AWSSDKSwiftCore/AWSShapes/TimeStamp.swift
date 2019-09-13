//
//  TimeStamp.swift
//  AWSSDKCore
//
//  Created by Yuki Takei/Adam Fowler on 2017/10/09.
//

import Foundation

public struct TimeStamp {
    
    public var stringValue: String? {
        guard let date = dateValue else { return nil }
        return TimeStamp.string(from:date)
    }
    
    public let dateValue: Date?

    public init(_ date: Date) {
        dateValue = date
    }
    
    public init(_ string: String) {
        self.dateValue = TimeStamp.date(from: string)
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
    private static var defaultDateFormatter : DateFormatter {
        let dateFormatter = DateFormatter()
        dateFormatter.locale = Locale(identifier: "en_US_POSIX")
        dateFormatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSS'Z'"
        dateFormatter.timeZone = TimeZone(secondsFromGMT: 0)
        return dateFormatter
    }

    /// date formatters for parsing date strings. Currently know of two different formats returned by AWS: iso and http
    static func createDateFormatters() -> [DateFormatter] {
        var dateFormatters : [DateFormatter] = [defaultDateFormatter]
        
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
        } else if let value = try? container.decode(String.self) {
                self.init(value)
        } else if let value = try? container.decode(Date.self) {
            self.init(value)
        } else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Expected string when decoding a Date")
        }
    }
    
    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(stringValue)
    }
}

