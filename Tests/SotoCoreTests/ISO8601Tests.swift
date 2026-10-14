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

import Testing

@testable import SotoCore

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif

@Suite("ISO8601 Date Parsing and Formatting")
struct ISO8601Tests {

    // MARK: - parseISO8601Date

    @Test("Parse standard ISO8601 date without fractional seconds")
    func parseWithoutFractionalSeconds() throws {
        let date = try #require(Date(iso8601: "2026-03-15T10:30:00Z"))
        // Verify by round-tripping: format back and check the string
        let formatted = date.iso8601
        #expect(formatted.contains("2026-03-15"))
        #expect(formatted.contains("10:30:00"))
    }

    @Test("Parse ISO8601 date with fractional seconds")
    func parseWithFractionalSeconds() throws {
        let date = try #require(Date(iso8601: "2026-02-18T16:59:23.216Z"))
        let formatted = date.iso8601
        #expect(formatted.contains("2026-02-18"))
        #expect(formatted.contains("16:59:23"))
    }

    @Test("Parse ISO8601 date with timezone offset")
    func parseWithTimezoneOffset() throws {
        let date = try #require(Date(iso8601: "2026-03-15T12:30:00+02:00"))
        let expected = try #require(Date(iso8601: "2026-03-15T10:30:00Z"))
        #expect(abs(date.timeIntervalSince1970 - expected.timeIntervalSince1970) < 1)
    }

    @Test("Parse returns nil for invalid date string")
    func parseInvalidString() {
        #expect(Date(iso8601: "not-a-date") == nil)
    }

    @Test("Parse returns nil for empty string")
    func parseEmptyString() {
        #expect(Date(iso8601: "") == nil)
    }

    @Test("Parse returns nil for partial date")
    func parsePartialDate() {
        #expect(Date(iso8601: "2026-03-15") == nil)
    }

    @Test("Parse returns nil for date without timezone")
    func parseDateWithoutTimezone() {
        #expect(Date(iso8601: "2026-03-15T10:30:00") == nil)
    }

    @Test("Parse epoch zero")
    func parseEpochZero() {
        let date = Date(iso8601: "1970-01-01T00:00:00Z")
        #expect(date != nil)
        #expect(abs(date!.timeIntervalSince1970) < 1)
    }

    @Test("Parse date far in the future")
    func parseFarFuture() {
        let date = Date(iso8601: "2099-12-31T23:59:59Z")
        #expect(date != nil)
        #expect(date!.timeIntervalSince1970 > 0)
    }

    @Test("Parse date with three-digit fractional seconds")
    func parseThreeDigitFractional() {
        let date = Date(iso8601: "2026-06-06T12:00:00.123Z")
        #expect(date != nil)
    }

    @Test("Parse date with high-precision fractional seconds")
    func parseHighPrecisionFractional() {
        let date = Date(iso8601: "2026-06-06T12:00:00.123456Z")
        #expect(date != nil)
    }

    // MARK: - formatISO8601Date

    @Test("Format date produces valid ISO8601 string")
    func formatProducesValidString() {
        let date = Date(timeIntervalSince1970: 1_773_577_800)
        let formatted = date.iso8601
        #expect(formatted.contains("2026-03-15"))
        #expect(formatted.contains("T"))
        #expect(formatted.hasSuffix("Z"))
    }

    @Test("Format date includes fractional seconds")
    func formatIncludesFractionalSeconds() {
        let date = Date(timeIntervalSince1970: 1_739_897_963.216)
        let formatted = date.iso8601
        #expect(formatted.contains("."))
    }

    @Test("Format epoch zero")
    func formatEpochZero() {
        let date = Date(timeIntervalSince1970: 0)
        let formatted = date.iso8601
        #expect(formatted.contains("1970-01-01"))
    }

    // MARK: - Round-trip

    @Test("Round-trip: format then parse returns same timestamp")
    func roundTrip() throws {
        let original = Date(timeIntervalSince1970: 1_773_577_800.5)
        let formatted = original.iso8601
        let parsed = try #require(Date(iso8601: formatted))
        #expect(abs(parsed.timeIntervalSince1970 - original.timeIntervalSince1970) < 0.01)
    }

    @Test("Round-trip: parse then format preserves date")
    func roundTripReverse() throws {
        let input = "2026-06-06T14:30:00.000Z"
        let parsed = try #require(Date(iso8601: input))
        let formatted = parsed.iso8601
        let reparsed = try #require(Date(iso8601: formatted))
        #expect(abs(reparsed.timeIntervalSince1970 - parsed.timeIntervalSince1970) < 0.01)
    }
}
