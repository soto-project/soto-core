//===----------------------------------------------------------------------===//
//
// This source file is part of the Soto for AWS open source project
//
// Copyright (c) 2017-2026 the Soto project authors
// Licensed under Apache License v2.0
//
// See LICENSE.txt for license information
// See CONTRIBUTORS.txt for the list of Soto project authors
//
// SPDX-License-Identifier: Apache-2.0
//
//===----------------------------------------------------------------------===//

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif

extension Date {
    @usableFromInline
    package init?(httpHeader: String) {
        #if os(macOS) || os(iOS) || os(tvOS) || os(watchOS) || os(visionOS)
        if #available(macOS 13, iOS 16, tvOS 16, watchOS 9, *) {
            try? self.init(httpHeader, strategy: .rfc9110)
        } else {
            guard let date = Self.httpDateFormatter.date(from: httpHeader) else {
                return nil
            }
            self = date
        }
        #else
        try? self.init(httpHeader, strategy: .rfc9110)
        #endif
    }

    @usableFromInline
    package var httpHeader: String {
        #if os(macOS) || os(iOS) || os(tvOS) || os(watchOS) || os(visionOS)
        if #available(macOS 13, iOS 16, tvOS 16, watchOS 9, *) {
            self.formatted(.rfc9110)
        } else {
            Self.httpDateFormatter.string(from: self)
        }
        #else
        self.formatted(.rfc9110)
        #endif
    }

    #if os(macOS) || os(iOS) || os(tvOS) || os(watchOS) || os(visionOS)
    private static let httpDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE, d MMM yyy HH:mm:ss z"
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter
    }()
    #endif
}

struct HTTPHeaderDateParsingError: Error {}

@available(macOS 13, iOS 16, tvOS 16, watchOS 9, *)
struct HTTPHeaderDateFormatStyle {
    let calendar: Calendar

    init() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .gmt
        self.calendar = calendar
    }
}

@available(macOS 13, iOS 16, tvOS 16, watchOS 9, *)
extension HTTPHeaderDateFormatStyle: ParseStrategy {
    func parse(_ input: String) throws -> Date {
        guard let components = self.components(from: input) else {
            throw HTTPHeaderDateParsingError()
        }
        guard components.isValidDate(in: self.calendar), let date = components.date else {
            throw HTTPHeaderDateParsingError()
        }
        return date
    }

    func components(from input: String) -> DateComponents? {
        var endIndex = input.endIndex
        // If the date string has a timezone in brackets, we need to remove it before parsing.
        if let bracket = input.firstIndex(of: "(") {
            endIndex = bracket
        }
        var s = input[input.startIndex..<endIndex]

        let asciiDigits = UInt8(ascii: "0")...UInt8(ascii: "9")

        return s.withUTF8 { buffer -> DateComponents? in
            func parseDay(_ it: inout UnsafeBufferPointer<UInt8>.Iterator) -> Int? {
                let first = it.nextAsciiDigit(skippingWhitespace: true)
                let second = it.next()
                guard let first = first, let second = second else { return nil }

                guard asciiDigits.contains(first) else { return nil }

                let day: Int
                if asciiDigits.contains(second) {
                    day = Int(first - UInt8(ascii: "0")) * 10 + Int(second - UInt8(ascii: "0"))
                } else {
                    day = Int(first - UInt8(ascii: "0"))
                }

                guard self.calendar.maximumRange(of: .day)!.contains(day) else { return nil }

                return day
            }

            func parseWeekDay(_ it: inout UnsafeBufferPointer<UInt8>.Iterator) -> Int? {
                let first = it.nextAsciiLetter()
                let second = it.nextAsciiLetter()
                let third = it.nextAsciiLetter()
                let comma = it.next()
                guard let first = first, let second = second, let third = third else { return nil }
                guard comma == UInt8(ascii: ",") else { return nil }
                guard let weekDay = weekDayMap[[first, second, third]] else { return nil }
                guard self.calendar.maximumRange(of: .weekday)!.contains(weekDay) else { return nil }
                return weekDay
            }

            func parseMonth(_ it: inout UnsafeBufferPointer<UInt8>.Iterator) -> Int? {
                let first = it.nextAsciiLetter(skippingWhitespace: true)
                let second = it.nextAsciiLetter()
                let third = it.nextAsciiLetter()
                guard let first = first, let second = second, let third = third else { return nil }
                guard first.isAsciiLetter else { return nil }
                guard let month = monthMap[[first, second, third]] else { return nil }
                guard self.calendar.maximumRange(of: .month)!.contains(month) else { return nil }
                return month
            }

            func parseYear(_ it: inout UnsafeBufferPointer<UInt8>.Iterator) -> Int? {
                let first = it.nextAsciiDigit(skippingWhitespace: true)
                let second = it.nextAsciiDigit()
                let third = it.nextAsciiDigit()
                let fourth = it.nextAsciiDigit()
                guard let first = first,
                    let second = second,
                    let third = third,
                    let fourth = fourth
                else { return nil }
                return Int(first - UInt8(ascii: "0")) * 1000
                    + Int(second - UInt8(ascii: "0")) * 100
                    + Int(third - UInt8(ascii: "0")) * 10
                    + Int(fourth - UInt8(ascii: "0"))
            }

            func parseHour(_ it: inout UnsafeBufferPointer<UInt8>.Iterator) -> Int? {
                let first = it.nextAsciiDigit(skippingWhitespace: true)
                let second = it.nextAsciiDigit()
                guard let first = first, let second = second else { return nil }
                let hour = Int(first - UInt8(ascii: "0")) * 10 + Int(second - UInt8(ascii: "0"))
                guard self.calendar.maximumRange(of: .hour)!.contains(hour) else { return nil }
                return hour
            }

            func parseMinute(_ it: inout UnsafeBufferPointer<UInt8>.Iterator) -> Int? {
                let first = it.nextAsciiDigit(skippingWhitespace: true)
                let second = it.nextAsciiDigit()
                guard let first = first, let second = second else { return nil }
                let minute = Int(first - UInt8(ascii: "0")) * 10 + Int(second - UInt8(ascii: "0"))
                guard self.calendar.maximumRange(of: .minute)!.contains(minute) else { return nil }
                return minute
            }

            func parseSecond(_ it: inout UnsafeBufferPointer<UInt8>.Iterator) -> Int? {
                let first = it.nextAsciiDigit(skippingWhitespace: true)
                let second = it.nextAsciiDigit()
                guard let first = first, let second = second else { return nil }
                let value = Int(first - UInt8(ascii: "0")) * 10 + Int(second - UInt8(ascii: "0"))
                guard self.calendar.maximumRange(of: .second)!.contains(value) else { return nil }
                return value
            }

            func parseTimezone(_ it: inout UnsafeBufferPointer<UInt8>.Iterator) -> Int? {
                let plusMinus = it.nextSkippingWhitespace()
                if let plusMinus, plusMinus == UInt8(ascii: "+") || plusMinus == UInt8(ascii: "-") {
                    let hour = parseHour(&it)
                    let minute = parseMinute(&it)
                    guard let hour = hour, let minute = minute else { return nil }
                    return (hour * 60 + minute) * (plusMinus == UInt8(ascii: "+") ? 1 : -1)
                } else if let first = plusMinus {
                    let second = it.nextAsciiLetter()
                    let third = it.nextAsciiLetter()

                    guard let second = second, let third = third else { return nil }
                    let abbr = [first, second, third]
                    return timezoneOffsetMap[abbr]
                }

                return nil
            }

            var it = buffer.makeIterator()

            guard let weekDay = parseWeekDay(&it) else { return nil }
            guard let day = parseDay(&it) else { return nil }
            guard let month = parseMonth(&it) else { return nil }
            guard let year = parseYear(&it) else { return nil }

            guard let hour = parseHour(&it) else { return nil }
            guard it.expect(UInt8(ascii: ":")) else { return nil }
            guard let minute = parseMinute(&it) else { return nil }
            guard it.expect(UInt8(ascii: ":")) else { return nil }
            guard let second = parseSecond(&it) else { return nil }

            guard let timezoneOffsetMinutes = parseTimezone(&it) else { return nil }

            return DateComponents(
                calendar: self.calendar,
                timeZone: TimeZone(secondsFromGMT: timezoneOffsetMinutes * 60),
                year: year,
                month: month,
                day: day,
                hour: hour,
                minute: minute,
                second: second,
                weekday: weekDay
            )
        }
    }
}

extension IteratorProtocol where Self.Element == UInt8 {
    mutating func expect(_ expected: UInt8) -> Bool {
        guard self.next() == expected else { return false }
        return true
    }

    mutating func nextSkippingWhitespace() -> UInt8? {
        while let c = self.next() {
            if c != UInt8(ascii: " ") {
                return c
            }
        }
        return nil
    }

    mutating func nextAsciiDigit(skippingWhitespace: Bool = false) -> UInt8? {
        while let c = self.next() {
            if skippingWhitespace {
                if c == UInt8(ascii: " ") {
                    continue
                }
            }
            switch c {
            case UInt8(ascii: "0")...UInt8(ascii: "9"): return c
            default: return nil
            }
        }
        return nil
    }

    mutating func nextAsciiLetter(skippingWhitespace: Bool = false) -> UInt8? {
        while let c = self.next() {
            if skippingWhitespace {
                if c == UInt8(ascii: " ") {
                    continue
                }
            }

            switch c {
            case UInt8(ascii: "A")...UInt8(ascii: "Z"),
                UInt8(ascii: "a")...UInt8(ascii: "z"):
                return c
            default: return nil
            }
        }
        return nil
    }
}

extension UInt8 {
    var isAsciiLetter: Bool {
        switch self {
        case UInt8(ascii: "A")...UInt8(ascii: "Z"),
            UInt8(ascii: "a")...UInt8(ascii: "z"):
            return true
        default: return false
        }
    }
}

let monthMap: [[UInt8]: Int] = [
    Array("Jan".utf8): 1,
    Array("Feb".utf8): 2,
    Array("Mar".utf8): 3,
    Array("Apr".utf8): 4,
    Array("May".utf8): 5,
    Array("Jun".utf8): 6,
    Array("Jul".utf8): 7,
    Array("Aug".utf8): 8,
    Array("Sep".utf8): 9,
    Array("Oct".utf8): 10,
    Array("Nov".utf8): 11,
    Array("Dec".utf8): 12,
]

let weekDayMap: [[UInt8]: Int] = [
    Array("Sun".utf8): 1,
    Array("Mon".utf8): 2,
    Array("Tue".utf8): 3,
    Array("Wed".utf8): 4,
    Array("Thu".utf8): 5,
    Array("Fri".utf8): 6,
    Array("Sat".utf8): 7,
]

let timezoneOffsetMap: [[UInt8]: Int] = [
    Array("UTC".utf8): 0,
    Array("GMT".utf8): 0,
    Array("EDT".utf8): -4 * 60,
    Array("CDT".utf8): -5 * 60,
    Array("MDT".utf8): -6 * 60,
    Array("PDT".utf8): -7 * 60,
]

@available(macOS 13, iOS 16, tvOS 16, watchOS 9, *)
extension HTTPHeaderDateFormatStyle: FormatStyle {
    func format(_ value: Date) -> String {
        let components = calendar.dateComponents([.weekday, .day, .month, .year, .hour, .minute, .second], from: value)
        var formatted = Self.dayNames[components.weekday! - 1]
        formatted.reserveCapacity(30)
        formatted += ", "
        formatted += Self.numberNames[components.day!]
        formatted += " "
        formatted += Self.monthNames[components.month! - 1]
        formatted += " "
        formatted += "\(components.year!)"
        formatted += " "
        formatted += Self.numberNames[components.hour!]
        formatted += ":"
        formatted += Self.numberNames[components.minute!]
        formatted += ":"
        formatted += Self.numberNames[components.second!]
        formatted += " GMT"
        return formatted
    }
    private static let dayNames = [
        "Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat",
    ]

    private static let monthNames = [
        "Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec",
    ]

    private static let numberNames = [
        "00", "01", "02", "03", "04", "05", "06", "07", "08", "09",
        "10", "11", "12", "13", "14", "15", "16", "17", "18", "19",
        "20", "21", "22", "23", "24", "25", "26", "27", "28", "29",
        "30", "31", "32", "33", "34", "35", "36", "37", "38", "39",
        "40", "41", "42", "43", "44", "45", "46", "47", "48", "49",
        "50", "51", "52", "53", "54", "55", "56", "57", "58", "59",
        "60", "61", "62", "63", "64", "65", "66", "67", "68", "69",
        "70", "71", "72", "73", "74", "75", "76", "77", "78", "79",
        "80", "81", "82", "83", "84", "85", "86", "87", "88", "89",
        "90", "91", "92", "93", "94", "95", "96", "97", "98", "99",
    ]
}

@available(macOS 13, iOS 16, tvOS 16, watchOS 9, *)
extension FormatStyle where Self == HTTPHeaderDateFormatStyle {
    static var rfc9110: Self { .init() }
}

@available(macOS 13, iOS 16, tvOS 16, watchOS 9, *)
extension ParseStrategy where Self == HTTPHeaderDateFormatStyle {
    static var rfc9110: Self { .init() }
}
