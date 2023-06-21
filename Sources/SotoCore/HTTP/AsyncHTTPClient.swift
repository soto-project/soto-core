//===----------------------------------------------------------------------===//
//
// This source file is part of the Soto for AWS open source project
//
// Copyright (c) 2017-2022 the Soto project authors
// Licensed under Apache License v2.0
//
// See LICENSE.txt for license information
// See CONTRIBUTORS.txt for the list of Soto project authors
//
// SPDX-License-Identifier: Apache-2.0
//
//===----------------------------------------------------------------------===//

import AsyncHTTPClient
import Logging
import NIOCore
import NIOHTTP1

extension AsyncHTTPClient.HTTPClient {
    /// Execute HTTP request
    /// - Parameters:
    ///   - request: HTTP request
    ///   - timeout: If execution is idle for longer than timeout then throw error
    ///   - eventLoop: eventLoop to run request on
    /// - Returns: EventLoopFuture that will be fulfilled with request response
    func execute(
        request: AWSHTTPRequest,
        timeout: TimeAmount,
        logger: Logger
    ) async throws -> AWSHTTPResponse {
        let requestBody: HTTPClientRequest.Body?

        switch request.body.payload {
        case .byteBuffer(let byteBuffer):
            requestBody = .bytes(byteBuffer)
        /* case .asyncSequence(let sequence, let length):
         requestBody = .stream(
             sequence,
             length: length.map { .known($0) } ?? .unknown
         ) */
        default:
            requestBody = nil
        }
        var httpRequest = HTTPClientRequest(url: request.url.absoluteString)
        httpRequest.method = request.method
        httpRequest.headers = request.headers
        httpRequest.body = requestBody

        let response = try await self.execute(httpRequest, timeout: timeout, logger: logger)
        return .init(
            status: response.status,
            headers: response.headers,
            body: .init(response.body, length: nil)
        )
    }
}
