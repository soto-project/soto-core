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

public class RequestEncodingContainer {
    var path: String
    var hostPrefix: String?
    var headers: HTTPHeaders = .init()
    var queryParams: [(key: String, value: String)] = []
    var body: AWSHTTPBody?

    init(headers: HTTPHeaders = .init(), queryParams: [(key: String, value: String)] = [], path: String, hostPrefix: String?) {
        self.headers = headers
        self.queryParams = queryParams
        self.path = path
        self.hostPrefix = hostPrefix
        self.body = nil
    }

    public func encodeHeader<Value>(_ value: Value, key: String) {
        self.headers.replaceOrAdd(name: key, value: "\(value)")
    }

    public func encodeHeader<Value>(_ value: Value?, key: String) {
        if let value = value {
            self.headers.replaceOrAdd(name: key, value: "\(value)")
        }
    }

    public func encodeHeader<Coder: CustomEncoder>(_ value: CustomCoding<Coder>, key: String) {
        if let string = Coder.string(from: value.wrappedValue) {
            self.headers.replaceOrAdd(name: key, value: string)
        }
    }

    public func encodeHeader<Coder: CustomEncoder>(_ value: OptionalCustomCoding<Coder>, key: String) {
        if let wrappedValue = value.wrappedValue, let string = Coder.string(from: wrappedValue) {
            self.headers.replaceOrAdd(name: key, value: string)
        }
    }

    public func encodeHeaders<Value>(_ value: [String: Value], withPrefix prefix: String) {
        for element in value {
            self.headers.replaceOrAdd(name: "\(prefix)\(element.key)", value: "\(element.value)")
        }
    }

    public func encodeQuery<Value>(_ value: Value, key: String) {
        self.queryParams.append((key: key, value: "\(value)"))
    }

    public func encodeQuery<Value>(_ value: Value?, key: String) {
        if let value = value {
            self.queryParams.append((key: key, value: "\(value)"))
        }
    }

    public func encodeQuery<Coder: CustomEncoder>(_ value: CustomCoding<Coder>, key: String) {
        if let string = Coder.string(from: value.wrappedValue) {
            self.queryParams.append((key: key, value: string))
        }
    }

    public func encodeQuery<Coder: CustomEncoder>(_ value: OptionalCustomCoding<Coder>, key: String) {
        if let wrappedValue = value.wrappedValue, let string = Coder.string(from: wrappedValue) {
            self.queryParams.append((key: key, value: string))
        }
    }

    public func encodeQuery<Value>(_ value: [Value], key: String) {
        for element in value {
            self.queryParams.append((key: key, value: "\(element)"))
        }
    }

    public func encodeQuery<Value>(_ value: [String: Value]) {
        for element in value {
            self.queryParams.append((key: element.key, value: "\(element.value)"))
        }
    }

    public func encodePath<Value>(_ value: Value, key: String) {
        self.path = self.path
            .replacingOccurrences(of: "{\(key)}", with: Self.urlEncodePathComponent(String(describing: value)))
            .replacingOccurrences(of: "{\(key)+}", with: Self.urlEncodePath(String(describing: value)))
    }

    public func encodeHostPrefix<Value>(_ value: Value, key: String) {
        self.hostPrefix = self.hostPrefix?
            .replacingOccurrences(of: "{\(key)}", with: Self.urlEncodePathComponent(String(describing: value)))
    }

    public func encodeBody(_ body: AWSHTTPBody) {
        self.body = body
    }

    /// percent encode query parameter value.
    private static func urlEncodeQueryParam(_ value: String) -> String {
        return value.addingPercentEncoding(withAllowedCharacters: AWSHTTPRequest.queryAllowedCharacters) ?? value
    }

    /// percent encode path value.
    private static func urlEncodePath(_ value: String) -> String {
        return value.addingPercentEncoding(withAllowedCharacters: AWSHTTPRequest.pathAllowedCharacters) ?? value
    }

    /// percent encode path component value. ie also encode "/"
    private static func urlEncodePathComponent(_ value: String) -> String {
        return value.addingPercentEncoding(withAllowedCharacters: AWSHTTPRequest.pathComponentAllowedCharacters) ?? value
    }
}

extension CodingUserInfoKey {
    public static var awsRequest: Self { return .init(rawValue: "soto.awsRequest")! }
}
