//===----------------------------------------------------------------------===//
//
// This source file is part of the Soto for AWS open source project
//
// Copyright (c) 2017-2023 the Soto project authors
// Licensed under Apache License v2.0
//
// See LICENSE.txt for license information
// See CONTRIBUTORS.txt for the list of Soto project authors
//
// SPDX-License-Identifier: Apache-2.0
//
//===----------------------------------------------------------------------===//

import Foundation
import Logging
import NIOHTTP1

/// Middleware that outputs the contents of requests being sent to AWS and the contents of the responses received.
public struct AWSLoggingMiddleware: AWSMiddlewareProtocol {
    @usableFromInline
    let log: @Sendable (@autoclosure () -> String) -> Void

    public typealias LoggingFunction = @Sendable (String) -> Void
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

    @inlinable
    public func handle(_ request: AWSHTTPRequest, context: AWSMiddlewareContext, next: AWSMiddlewareNextHandler) async throws -> AWSHTTPResponse {
        self.log(
            "Request:\n" +
                "  \(context.operation)\n" +
                "  \(request.method) \(request.url)\n" +
                "  Headers: \(self.getHeadersOutput(request.headers))\n" +
                "  Body: \(self.getBodyOutput(request.body))"
        )
        let response = try await next(request, context)
        self.log(
            "Response:\n" +
                "  Status : \(response.status.code)\n" +
                "  Headers: \(self.getHeadersOutput(HTTPHeaders(response.headers.map { ($0, "\($1)") })))\n" +
                "  Body: \(self.getBodyOutput(response.body))"
        )
        return response
    }

    @usableFromInline
    func getBodyOutput(_ body: AWSHTTPBody) -> String {
        var output = ""
        switch body.storage {
        case .byteBuffer(let buffer):
            output += "\n  "
            output += "\(String(buffer: buffer))"
        default:
            output += "binary data"
        }
        return output
    }

    @usableFromInline
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
}
