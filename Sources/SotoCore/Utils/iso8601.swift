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
    package init?(iso8601 string: String) {
        #if canImport(FoundationEssentials)
        if let date = try? Date(string, strategy: Date.ISO8601FormatStyle(includingFractionalSeconds: true)) {
            self = date
        } else if let date = try? Date(string, strategy: .iso8601) {
            self = date
        } else {
            return nil
        }
        #else
        if #available(iOS 15, macOS 12, tvOS 15, watchOS 8, *) {
            if let date = try? Date(string, strategy: Date.ISO8601FormatStyle(includingFractionalSeconds: true)) {
                self = date
            } else if let date = try? Date(string, strategy: .iso8601) {
                self = date
            } else {
                return nil
            }
        } else {
            if let date = Self.iso8601FormatterWithSeconds.date(from: string) {
                self = date
            } else if let date = Self.iso8601Formatter.date(from: string) {
                self = date
            } else {
                return nil
            }
        }
        #endif
    }

    @usableFromInline
    package var iso8601: String {
        #if canImport(FoundationEssentials)
        return self.formatted(Date.ISO8601FormatStyle(includingFractionalSeconds: true))
        #else
        if #available(iOS 15, macOS 12, tvOS 15, watchOS 8, *) {
            return self.formatted(Date.ISO8601FormatStyle(includingFractionalSeconds: true))
        } else {
            return Self.iso8601FormatterWithSeconds.string(from: self)
        }
        #endif
    }

    #if os(macOS) || os(iOS) || os(tvOS) || os(watchOS) || os(visionOS)
    private static var iso8601Formatter: ISO8601DateFormatter {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withFullDate, .withFullTime]
        return formatter
    }
    private static var iso8601FormatterWithSeconds: ISO8601DateFormatter {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withFullDate, .withFullTime, .withFractionalSeconds]
        return formatter
    }

    #endif
}
