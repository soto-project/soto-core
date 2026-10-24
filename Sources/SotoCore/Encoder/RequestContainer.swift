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

public import HTTPTypes
import NIOConcurrencyHelpers
import SotoSignerV4

#if canImport(FoundationEssentials)
public import FoundationEssentials
#else
public import Foundation
#endif

/// Request container used during Codable `encode(to:)` that allows for encoding data into
/// the request that is not part of standard Codable output
@_spi(SotoInternal)
public final class RequestEncodingContainer: Sendable {
    struct _Internal {
        @usableFromInline
        var path: String
        @usableFromInline
        var hostPrefix: String?
        @usableFromInline
        var headers: HTTPFields = .init()
        @usableFromInline
        var queryParams: [(key: String, value: String)] = []
        @usableFromInline
        var body: AWSHTTPBody?

        init(headers: HTTPFields, queryParams: [(key: String, value: String)], path: String, hostPrefix: String?) {
            self.headers = headers
            self.queryParams = queryParams
            self.path = path
            self.hostPrefix = hostPrefix
            self.body = nil
        }
    }
    let _internal: NIOLockedValueBox<_Internal>

    @usableFromInline
    var path: String {
        get {
            self._internal.withLockedValue { $0.path }
        }
        set {
            self._internal.withLockedValue { $0.path = newValue }
        }
    }
    @usableFromInline
    var hostPrefix: String? {
        get {
            self._internal.withLockedValue { $0.hostPrefix }
        }
        set {
            self._internal.withLockedValue { $0.hostPrefix = newValue }
        }
    }
    @usableFromInline
    var headers: HTTPFields {
        get {
            self._internal.withLockedValue { $0.headers }
        }
        set {
            self._internal.withLockedValue { $0.headers = newValue }
        }
    }
    @usableFromInline
    var queryParams: [(key: String, value: String)] {
        get {
            self._internal.withLockedValue { $0.queryParams }
        }
        set {
            self._internal.withLockedValue { $0.queryParams = newValue }
        }
    }
    @usableFromInline
    var body: AWSHTTPBody? {
        get {
            self._internal.withLockedValue { $0.body }
        }
        set {
            self._internal.withLockedValue { $0.body = newValue }
        }
    }

    init(headers: HTTPFields = .init(), queryParams: [(key: String, value: String)] = [], path: String, hostPrefix: String?) {
        self._internal = .init(.init(headers: headers, queryParams: queryParams, path: path, hostPrefix: hostPrefix))
    }

    /// Build URL from Request encoding container values
    func buildURL(endpoint: String) throws -> URL {
        guard var urlComponents = URLComponents(string: "\(endpoint)\(self.path)") else {
            throw AWSClient.ClientError.invalidURL
        }

        if let hostPrefix = self.hostPrefix, let host = urlComponents.host {
            urlComponents.host = hostPrefix + host
        }

        // add queries from the parsed path to the query params list
        var queryParams: [(key: String, value: String)] = self.queryParams
        if let pathQueryItems = urlComponents.queryItems {
            for item in pathQueryItems {
                queryParams.append((key: item.name, value: item.value ?? ""))
            }
        }

        // Set query params. Percent encode these ourselves as Foundation and AWS disagree on what should be percent encoded in the query values
        // Also the signer doesn't percent encode the queries so they need to be encoded here
        if queryParams.count > 0 {
            let urlQueryString =
                queryParams
                .map { (key: $0.key, value: $0.value) }
                .sorted {
                    // sort by key. if key are equal then sort by value. Cannot sort by key and value combined as
                    // in the situation where one key is a prefix of another it will use the `=` sign in the sorting
                    if $0.key < $1.key { return true }
                    if $0.key > $1.key { return false }
                    return $0.value < $1.value
                }
                .map { "\($0.key)=\(Self.urlEncodeQueryParam($0.value))" }
                .joined(separator: "&")
            urlComponents.percentEncodedQuery = urlQueryString
        }

        guard let url = urlComponents.url else {
            throw AWSClient.ClientError.invalidURL
        }
        return url
    }

    // MARK: Header encoding

    /// Write value to header
    @inlinable
    public func encodeHeader(_ value: some Any, key: String) {
        self.headers[.init(key)!] = "\(value)"
    }

    /// Write optional value to header
    @inlinable
    public func encodeHeader(_ value: (some Any)?, key: String) {
        if let value {
            self.encodeHeader(value, key: key)
        }
    }

    /// Write value inside CustomCoding property wrapper to header
    @inlinable
    public func encodeHeader<Coder: CustomEncoder>(_ value: CustomCoding<Coder>, key: String) {
        if let string = Coder.string(from: value.wrappedValue) {
            self.headers[.init(key)!] = string
        }
    }

    /// Write value inside OptionalCustomCoding property wrapper to header
    @inlinable
    public func encodeHeader<Coder: CustomEncoder>(_ value: OptionalCustomCoding<Coder>, key: String) {
        if let wrappedValue = value.wrappedValue, let string = Coder.string(from: wrappedValue) {
            self.headers[.init(key)!] = string
        }
    }

    /// Write date to headers
    @inlinable
    public func encodeHeader(_ value: Date, key: String) {
        self.encodeHeader(HTTPHeaderDateCoder.string(from: value), key: key)
    }

    /// Write date to headers
    @inlinable
    public func encodeHeader(_ value: Date?, key: String) {
        if let value {
            self.encodeHeader(value, key: key)
        }
    }

    /// Write dictionary key value pairs to headers with prefix added to the keys
    @inlinable
    public func encodeHeader(_ value: [String: some Any], key prefix: String) {
        for element in value {
            self.headers[.init("\(prefix)\(element.key)")!] = "\(element.value)"
        }
    }

    /// Write optional dictionary key value pairs to headers with prefix added to the keys
    @inlinable
    public func encodeHeader(_ value: [String: some Any]?, key prefix: String) {
        if let value {
            self.encodeHeader(value, key: prefix)
        }
    }

    // MARK: Query encoding

    /// Write value to query
    @inlinable
    public func encodeQuery(_ value: some Any, key: String) {
        self.queryParams.append((key: key, value: "\(value)"))
    }

    /// Write optional value to query
    @inlinable
    public func encodeQuery(_ value: (some Any)?, key: String) {
        if let value {
            self.queryParams.append((key: key, value: "\(value)"))
        }
    }

    /// Write value inside CustomCoding property wrapper to query
    @inlinable
    public func encodeQuery<Coder: CustomEncoder>(_ value: CustomCoding<Coder>, key: String) {
        if let string = Coder.string(from: value.wrappedValue) {
            self.queryParams.append((key: key, value: string))
        }
    }

    /// Write value inside OptionalCustomCoding property wrapper to query
    @inlinable
    public func encodeQuery<Coder: CustomEncoder>(_ value: OptionalCustomCoding<Coder>, key: String) {
        if let wrappedValue = value.wrappedValue, let string = Coder.string(from: wrappedValue) {
            self.queryParams.append((key: key, value: string))
        }
    }

    /// Write date to query
    @inlinable
    public func encodeQuery(_ value: Date, key: String) {
        self.encodeQuery(UnixEpochDateCoder.string(from: value), key: key)
    }

    /// Write optional date to query
    @inlinable
    public func encodeQuery(_ value: Date?, key: String) {
        if let value {
            self.encodeQuery(value, key: key)
        }
    }

    /// Write array as a series of query values
    @inlinable
    public func encodeQuery(_ value: [some Any], key: String) {
        for element in value {
            self.queryParams.append((key: key, value: "\(element)"))
        }
    }

    /// Write dictionary key value pairs as query key value pairs
    @inlinable
    public func encodeQuery(_ value: [String: some Any]) {
        for element in value {
            self.queryParams.append((key: element.key, value: "\(element.value)"))
        }
    }

    /// Write optional array as a series of query values
    @inlinable
    public func encodeQuery(_ value: [some Any]?, key: String) {
        if let value {
            self.encodeQuery(value, key: key)
        }
    }

    /// Write optional dictionary key value pairs as query key value pairs
    @inlinable
    public func encodeQuery(_ value: [String: some Any]?) {
        if let value {
            self.encodeQuery(value)
        }
    }

    // MARK: Path encoding

    /// Write value into URI path
    @inlinable
    public func encodePath(_ value: some Any, key: String) {
        self.path = self.path
            .replacing("{\(key)}", with: Self.urlEncodePathComponent(String(describing: value)))
            .replacing("{\(key)+}", with: Self.urlEncodePath(String(describing: value)))
    }

    /// Write value into hostname
    @inlinable
    public func encodeHostPrefix(_ value: some Any, key: String) {
        self.hostPrefix = self.hostPrefix?
            .replacing("{\(key)}", with: Self.urlEncodePathComponent(String(describing: value)))
    }

    /// percent encode query parameter value.
    internal static func urlEncodeQueryParam(_ value: String) -> String {
        value.addingAWSPercentEncoding(forURLComponent: .uriEncode)
    }

    /// percent encode path value.
    @usableFromInline
    internal static func urlEncodePath(_ value: String) -> String {
        value.addingAWSPercentEncoding(forURLComponent: .path)
    }

    /// percent encode path component value. ie also encode "/"
    @usableFromInline
    internal static func urlEncodePathComponent(_ value: String) -> String {
        value.addingAWSPercentEncoding(forURLComponent: .pathComponent)
    }
}

extension CodingUserInfoKey {
    public static var awsRequest: Self { .init(rawValue: "soto.awsRequest")! }
}
