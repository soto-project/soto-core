//===----------------------------------------------------------------------===//
//
// This source file is part of the Soto for AWS open source project
//
// Copyright (c) 2017-2020 the Soto project authors
// Licensed under Apache License v2.0
//
// See LICENSE.txt for license information
// See CONTRIBUTORS.txt for the list of Soto project authors
//
// SPDX-License-Identifier: Apache-2.0
//
//===----------------------------------------------------------------------===//

#if compiler(>=5.6) && canImport(_Concurrency)
@_predatesConcurrency import Logging
#else
import Logging
#endif
import NIOHTTP1

/// Context object sent to `AWSServiceMiddleware` `chain` functions
public struct AWSMiddlewareContext {
    public let options: AWSServiceConfig.Options
}

/// Middleware protocol. Gives ability to process requests before they are sent to AWS and process responses before they are converted into output shapes
public protocol AWSServiceMiddleware: SotoSendable {
    /// Process AWSRequest before it is converted to a HTTPClient Request to be sent to AWS
    func chain(request: AWSRequest, context: AWSMiddlewareContext) throws -> AWSRequest

    /// Process response before it is converted to an output AWSShape
    func chain(response: AWSResponse, context: AWSMiddlewareContext) throws -> AWSResponse
}

/// Default versions of protocol functions
public extension AWSServiceMiddleware {
    func chain(request: AWSRequest, context: AWSMiddlewareContext) throws -> AWSRequest {
        return request
    }

    func chain(response: AWSResponse, context: AWSMiddlewareContext) throws -> AWSResponse {
        return response
    }
}

/// Middleware struct that outputs the contents of requests being sent to AWS and the bodies of the responses received
public struct AWSLoggingMiddleware: AWSServiceMiddleware {
    #if compiler(>=5.6) && canImport(_Concurrency)
    public typealias LoggingFunction = @Sendable (String) -> Void
    #else
    public typealias LoggingFunction = (String) -> Void
    #endif
    /// initialize AWSLoggingMiddleware
    /// - parameters:
    ///     - log: Function to call with logging output
    public init(log: @escaping LoggingFunction = { print($0) }) {
        self.log = { log($0()) }
    }

    /// initialize AWSLoggingMiddleware to use Logger
    /// - Parameters:
    ///   - logger: Logger to use
    ///   - logLevel: Log level to output at
    public init(logger: Logger, logLevel: Logger.Level = .info) {
        self.log = { logger.log(level: logLevel, "\($0())") }
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
    public func chain(request: AWSRequest, context: AWSMiddlewareContext) throws -> AWSRequest {
        self.log(
            "Request:\n" +
                "  \(request.operation)\n" +
                "  \(request.httpMethod) \(request.url)\n" +
                "  Headers: \(self.getHeadersOutput(request.httpHeaders))\n" +
                "  Body: \(self.getBodyOutput(request.body))"
        )
        return request
    }

    /// output response
    public func chain(response: AWSResponse, context: AWSMiddlewareContext) throws -> AWSResponse {
        self.log(
            "Response:\n" +
                "  Status : \(response.status.code)\n" +
                "  Headers: \(self.getHeadersOutput(HTTPHeaders(response.headers.map { ($0, "\($1)") })))\n" +
                "  Body: \(self.getBodyOutput(response.body))"
        )
        return response
    }
    #if compiler(>=5.6) && canImport(_Concurrency)
    let log: @Sendable (@autoclosure () -> String) -> Void
    #else
    let log: (@autoclosure () -> String) -> Void
    #endif
}
