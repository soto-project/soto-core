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

import Foundation

/// Parse an ISO8601 date string, handling both with and without fractional seconds.
/// AWS CLI writes dates with fractional seconds (e.g., "2026-02-18T16:59:23.216Z"),
/// but not all date strings have them.
func parseISO8601Date(_ string: String) -> Date? {
    #if canImport(FoundationEssentials)
    if let date = try? Date(string, strategy: .iso8601) {
        return date
    }
    if let date = try? Date(string, strategy: Date.ISO8601FormatStyle(includingFractionalSeconds: true)) {
        return date
    }
    #else
    if #available(iOS 15, macOS 12, tvOS 15, watchOS 8, *) {
        if let date = try? Date(string, strategy: .iso8601) {
            return date
        }
        if let date = try? Date(string, strategy: Date.ISO8601FormatStyle(includingFractionalSeconds: true)) {
            return date
        }
    } else {
        let formatterWithSeconds = ISO8601DateFormatter()
        formatterWithSeconds.formatOptions = [.withFullDate, .withFullTime, .withFractionalSeconds]
        if let date = formatterWithSeconds.date(from: string) {
            return date
        }
        let formatterWithoutSeconds = ISO8601DateFormatter()
        formatterWithoutSeconds.formatOptions = [.withFullDate, .withFullTime]
        if let date = formatterWithoutSeconds.date(from: string) {
            return date
        }
    }
    #endif
    return nil
}

/// Format a Date as an ISO8601 string with fractional seconds.
func formatISO8601Date(_ date: Date) -> String? {
    #if canImport(FoundationEssentials)
    return date.formatted(Date.ISO8601FormatStyle(includingFractionalSeconds: true))
    #else
    if #available(iOS 15, macOS 12, tvOS 15, watchOS 8, *) {
        return date.formatted(Date.ISO8601FormatStyle(includingFractionalSeconds: true))
    } else {
        let formatterWithSeconds = ISO8601DateFormatter()
        formatterWithSeconds.formatOptions = [.withFullDate, .withFullTime, .withFractionalSeconds]
        return formatterWithSeconds.string(from: date)
    }
    #endif
}
