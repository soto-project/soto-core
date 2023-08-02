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

import Logging
import NIOHTTP1
import SotoSignerV4

/// Middleware that throws errors for non 2xx responses from AWS
struct ErrorHandlingMiddleware: AWSMiddlewareProtocol {
    let options: AWSClient.Options

    func handle(_ request: AWSHTTPRequest, context: AWSMiddlewareContext, next: (AWSHTTPRequest, AWSMiddlewareContext) async throws -> AWSHTTPResponse) async throws -> AWSHTTPResponse {
        let response = try await next(request, context)

        // if response has an HTTP status code outside 2xx then throw an error
        guard (200..<300).contains(response.status.code) else {
            let error = await self.createError(for: response, context: context)
            throw error
        }

        return response
    }

    /// Create error from HTTPResponse. This is only called if we received an unsuccessful http status code.
    internal func createError(for response: AWSHTTPResponse, context: AWSMiddlewareContext) async -> Error {
        // if we can create an AWSResponse and create an error from it return that
        var response = response
        do {
            try await response.collateBody()
        } catch {
            // else return "Unhandled error message" with rawBody attached
            let context = AWSErrorContext(
                message: "Unhandled Error",
                responseCode: response.status,
                headers: response.headers
            )
            return AWSRawError(rawBody: nil, context: context)
        }
        if let error = response.generateError(
            serviceConfig: context.serviceConfig,
            logLevel: self.options.errorLogLevel,
            logger: context.logger
        ) {
            return error
        } else {
            // else return "Unhandled error message" with rawBody attached
            let context = AWSErrorContext(
                message: "Unhandled Error",
                responseCode: response.status,
                headers: response.headers
            )
            let responseBody: String?
            switch response.body.storage {
            case .byteBuffer(let buffer):
                responseBody = String(buffer: buffer)
            default:
                responseBody = nil
            }
            return AWSRawError(rawBody: responseBody, context: context)
        }
    }
}
