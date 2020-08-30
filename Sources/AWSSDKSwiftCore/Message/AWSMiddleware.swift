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

import NIOHTTP1

/// Middleware protocol. Gives ability to process requests before they are sent to AWS and process responses before they are converted into output shapes
public protocol AWSServiceMiddleware {
    /// Process AWSRequest before it is converted to a HTTPClient Request to be sent to AWS
    func chain(request: AWSRequest) throws -> AWSRequest

    /// Process response before it is converted to an output AWSShape
    func chain(response: AWSResponse) throws -> AWSResponse
}

/// Default versions of protocol functions
public extension AWSServiceMiddleware {
    func chain(request: AWSRequest) throws -> AWSRequest {
        return request
    }

    func chain(response: AWSResponse) throws -> AWSResponse {
        return response
    }
}

/// Middleware struct that outputs the contents of requests being sent to AWS and the bodies of the responses received
public struct AWSLoggingMiddleware: AWSServiceMiddleware {
    /// initialize AWSLoggingMiddleware class
    /// - parameters:
    ///     - log: Function to call with logging output
    public init(log: @escaping (String) -> Void = { print($0) }) {
        self.log = log
    }

    func getBodyOutput(_ body: Body) -> String {
        var output = ""
        switch body {
        case .xml(let element):
            output += "\n  "
            output += element.description
        case .json(let buffer):
            output += "\n  "
            output += buffer.getString(at: buffer.readerIndex, length: buffer.readableBytes) ?? "Failed to convert JSON response to UTF8"
        case .raw(let payload):
            output += "raw (\(payload.size?.description ?? "unknown") bytes)"
        case .text(let string):
            output += "\n  \(string)"
        case .empty:
            output += "empty"
        }
        return output
    }

    func getHeadersOutput(_ headers: HTTPHeaders) -> String {
        if headers.count == 0 {
            return "[]"
        }
        var output = "["
        for header in headers {
            output += "\n    \(header.name) : \(header.value)"
        }
        return output + "\n  ]"
    }

    /// output request
    public func chain(request: AWSRequest) throws -> AWSRequest {
        self.log("Request:")
        self.log("  \(request.operation)")
        self.log("  \(request.httpMethod) \(request.url)")
        self.log("  Headers: " + self.getHeadersOutput(request.httpHeaders))
        self.log("  Body: " + self.getBodyOutput(request.body))
        return request
    }

    /// output response
    public func chain(response: AWSResponse) throws -> AWSResponse {
        self.log("Response:")
        self.log("  Status : \(response.status.code)")
        self.log("  Headers: " + self.getHeadersOutput(HTTPHeaders(response.headers.map { ($0, "\($1)") })))
        self.log("  Body: " + self.getBodyOutput(response.body))
        return response
    }

    let log: (String) -> Void
}
