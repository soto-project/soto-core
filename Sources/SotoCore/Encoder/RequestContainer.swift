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

import struct Foundation.CharacterSet
import struct Foundation.Date
import struct Foundation.URL
import struct Foundation.URLComponents

/// Request container used during Codable `encode(to:)` that allows for encoding data into
/// the request that is not part of standard Codable output
public class RequestEncodingContainer {
    @usableFromInline
    var path: String
    @usableFromInline
    var hostPrefix: String?
    @usableFromInline
    var headers: HTTPHeaders = .init()
    @usableFromInline
    var queryParams: [(key: String, value: String)] = []
    @usableFromInline
    var body: AWSHTTPBody?

    init(headers: HTTPHeaders = .init(), queryParams: [(key: String, value: String)] = [], path: String, hostPrefix: String?) {
        self.headers = headers
        self.queryParams = queryParams
        self.path = path
        self.hostPrefix = hostPrefix
        self.body = nil
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
            let urlQueryString = queryParams
                .map { (key: $0.key, value: "\($0.value)") }
                .sorted {
                    // sort by key. if key are equal then sort by value
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
    public func encodeHeader<Value>(_ value: Value, key: String) {
        self.headers.replaceOrAdd(name: key, value: "\(value)")
    }

    /// Write optional value to header
    @inlinable
    public func encodeHeader<Value>(_ value: Value?, key: String) {
        if let value = value {
            self.encodeHeader(value, key: key)
        }
    }

    /// Write value inside CustomCoding property wrapper to header
    @inlinable
    public func encodeHeader<Coder: CustomEncoder>(_ value: CustomCoding<Coder>, key: String) {
        if let string = Coder.string(from: value.wrappedValue) {
            self.headers.replaceOrAdd(name: key, value: string)
        }
    }

    /// Write value inside OptionalCustomCoding property wrapper to header
    @inlinable
    public func encodeHeader<Coder: CustomEncoder>(_ value: OptionalCustomCoding<Coder>, key: String) {
        if let wrappedValue = value.wrappedValue, let string = Coder.string(from: wrappedValue) {
            self.headers.replaceOrAdd(name: key, value: string)
        }
    }

    /// Write dictionary key value pairs to headers with prefix added to the keys
    @inlinable
    public func encodeHeader(_ value: Date, key: String) {
        self.encodeHeader(HTTPHeaderDateCoder.string(from: value), key: key)
    }

    /// Write dictionary key value pairs to headers with prefix added to the keys
    @inlinable
    public func encodeHeader<Value>(_ value: [String: Value], key prefix: String) {
        for element in value {
            self.headers.replaceOrAdd(name: "\(prefix)\(element.key)", value: "\(element.value)")
        }
    }

    /// Write optional dictionary key value pairs to headers with prefix added to the keys
    @inlinable
    public func encodeHeader<Value>(_ value: [String: Value]?, key prefix: String) {
        if let value = value {
            self.encodeHeader(value, key: prefix)
        }
    }

    // MARK: Query encoding

    /// Write value to query
    @inlinable
    public func encodeQuery<Value>(_ value: Value, key: String) {
        self.queryParams.append((key: key, value: "\(value)"))
    }

    /// Write optional value to query
    @inlinable
    public func encodeQuery<Value>(_ value: Value?, key: String) {
        if let value = value {
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

    /// Write array as a series of query values
    @inlinable
    public func encodeQuery<Value>(_ value: [Value], key: String) {
        for element in value {
            self.queryParams.append((key: key, value: "\(element)"))
        }
    }

    /// Write dictionary key value pairs as query key value pairs
    @inlinable
    public func encodeQuery<Value>(_ value: [String: Value]) {
        for element in value {
            self.queryParams.append((key: element.key, value: "\(element.value)"))
        }
    }

    /// Write optional array as a series of query values
    @inlinable
    public func encodeQuery<Value>(_ value: [Value]?, key: String) {
        if let value = value {
            self.encodeQuery(value, key: key)
        }
    }

    /// Write optional dictionary key value pairs as query key value pairs
    @inlinable
    public func encodeQuery<Value>(_ value: [String: Value]?) {
        if let value = value {
            self.encodeQuery(value)
        }
    }

    /// Write value into URI path
    @inlinable
    public func encodePath<Value>(_ value: Value, key: String) {
        self.path = self.path
            .replacingOccurrences(of: "{\(key)}", with: Self.urlEncodePathComponent(String(describing: value)))
            .replacingOccurrences(of: "{\(key)+}", with: Self.urlEncodePath(String(describing: value)))
    }

    /// Write value into hostname
    @inlinable
    public func encodeHostPrefix<Value>(_ value: Value, key: String) {
        self.hostPrefix = self.hostPrefix?
            .replacingOccurrences(of: "{\(key)}", with: Self.urlEncodePathComponent(String(describing: value)))
    }

    /// percent encode query parameter value.
    internal static func urlEncodeQueryParam(_ value: String) -> String {
        return value.addingPercentEncoding(withAllowedCharacters: Self.queryAllowedCharacters) ?? value
    }

    /// percent encode path value.
    @usableFromInline
    internal static func urlEncodePath(_ value: String) -> String {
        return value.addingPercentEncoding(withAllowedCharacters: Self.pathAllowedCharacters) ?? value
    }

    /// percent encode path component value. ie also encode "/"
    @usableFromInline
    internal static func urlEncodePathComponent(_ value: String) -> String {
        return value.addingPercentEncoding(withAllowedCharacters: Self.pathComponentAllowedCharacters) ?? value
    }

    /// this list of query allowed characters comes from https://docs.aws.amazon.com/AmazonS3/latest/API/sig-v4-header-based-auth.html
    static let queryAllowedCharacters = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")
    @usableFromInline
    static let pathAllowedCharacters = CharacterSet.urlPathAllowed.subtracting(.init(charactersIn: "+"))
    @usableFromInline
    static let pathComponentAllowedCharacters = CharacterSet.urlPathAllowed.subtracting(.init(charactersIn: "+/"))
}

extension CodingUserInfoKey {
    public static var awsRequest: Self { return .init(rawValue: "soto.awsRequest")! }
}
