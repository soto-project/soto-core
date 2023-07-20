//===----------------------------------------------------------------------===//
//
// This source file is part of the Soto for AWS open source project
//
// Copyright (c) 2023 the Soto project authors
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

public struct HeaderDecodingError: Error {
    let header: String
    let message: String

    static func headerNotFound(_ header: String) -> Self { .init(header: header, message: "Header not found") }
    static func typeMismatch(_ header: String, expectedType: String) -> Self { .init(header: header, message: "Cannot convert header to \(expectedType)") }
}

public struct ResponseDecodingContainer {
    let response: AWSResponse

    public func decode<Value: RawRepresentable>(_ type: Value.Type = Value.self, forHeader header: String) throws -> Value where Value.RawValue == String {
        guard let headerValue = response.headers[header].first else {
            throw HeaderDecodingError.headerNotFound(header)
        }
        if let result = Value(rawValue: headerValue) {
            return result
        } else {
            throw HeaderDecodingError.typeMismatch(header, expectedType: "\(Value.self)")
        }
    }

    public func decode<Value: LosslessStringConvertible>(_ type: Value.Type = Value.self, forHeader header: String) throws -> Value {
        guard let headerValue = response.headers[header].first else {
            throw HeaderDecodingError.headerNotFound(header)
        }
        if let result = Value(headerValue) {
            return result
        } else {
            throw HeaderDecodingError.typeMismatch(header, expectedType: "\(Value.self)")
        }
    }

    public func decodeStatus<Value: FixedWidthInteger>(_: Value.Type = Value.self) -> Value {
        return Value(self.response.status.code)
    }

    public func decodePayload() -> AWSHTTPBody {
        return self.response.body
    }

    public func decodeEventStream<Event>() -> AWSEventStream<Event> {
        return .init(self.response.body)
    }

    public func decode(_ type: Date.Type = Date.self, forHeader header: String) throws -> Date {
        guard let headerValue = response.headers[header].first else {
            throw HeaderDecodingError.headerNotFound(header)
        }
        let dateFormatter = DateFormatter()
        dateFormatter.locale = Locale(identifier: "en_US_POSIX")
        dateFormatter.dateFormat = "EEE, d MMM yyy HH:mm:ss z"
        dateFormatter.timeZone = TimeZone(secondsFromGMT: 0)
        if let result = dateFormatter.date(from: headerValue) {
            return result
        } else {
            throw HeaderDecodingError.typeMismatch(header, expectedType: "Date")
        }
    }

    public func decodeIfPresent<Value: RawRepresentable>(_ type: Value.Type = Value.self, forHeader header: String) throws -> Value? where Value.RawValue == String {
        guard let headerValue = response.headers[header].first else { return nil }
        if let result = Value(rawValue: headerValue) {
            return result
        } else {
            throw HeaderDecodingError.typeMismatch(header, expectedType: "\(Value.self)")
        }
    }

    public func decodeIfPresent<Value: LosslessStringConvertible>(_ type: Value.Type = Value.self, forHeader header: String) throws -> Value? {
        guard let headerValue = response.headers[header].first else { return nil }
        if let result = Value(headerValue) {
            return result
        } else {
            throw HeaderDecodingError.typeMismatch(header, expectedType: "\(Value.self)")
        }
    }

    public func decodeIfPresent(_ type: Date.Type = Date.self, forHeader header: String) throws -> Date? {
        guard let headerValue = response.headers[header].first else { return nil }
        let dateFormatter = DateFormatter()
        dateFormatter.locale = Locale(identifier: "en_US_POSIX")
        dateFormatter.dateFormat = "EEE, d MMM yyy HH:mm:ss z"
        dateFormatter.timeZone = TimeZone(secondsFromGMT: 0)
        if let result = dateFormatter.date(from: headerValue) {
            return result
        } else {
            throw HeaderDecodingError.typeMismatch(header, expectedType: "Date")
        }
    }

    public func decodeIfPresent(_ type: [String: String].Type = [String: String].self, forHeader header: String) throws -> [String: String]? {
        let headers = self.response.headers.compactMap { $0.name.hasPrefix(header) ? $0 : nil }
        if headers.count == 0 {
            return nil
        }
        return [String: String](headers.map { (key: String($0.name.dropFirst(header.count)), value: $0.value) }) { first, _ in first }
    }
}

extension CodingUserInfoKey {
    public static var awsResponse: Self { return .init(rawValue: "soto.awsResponse")! }
}
