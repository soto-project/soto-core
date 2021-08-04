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

import Baggage
import AsyncHTTPClient
import NIO
import NIOHTTP1

/// comply with AWSHTTPClient protocol
extension AsyncHTTPClient.HTTPClient: AWSHTTPClient {
    /// Execute HTTP request
    /// - Parameters:
    ///   - request: HTTP request
    ///   - timeout: If execution is idle for longer than timeout then throw error
    ///   - eventLoop: eventLoop to run request on
    /// - Returns: EventLoopFuture that will be fulfilled with request response
    public func execute(request: AWSHTTPRequest, timeout: TimeAmount, on eventLoop: EventLoop, context: LoggingContext) -> EventLoopFuture<AWSHTTPResponse> {
        let requestBody: AsyncHTTPClient.HTTPClient.Body?
        var requestHeaders = request.headers

        switch request.body.payload {
        case .byteBuffer(let byteBuffer):
            requestBody = .byteBuffer(byteBuffer)
        case .stream(let reader):
            requestHeaders = reader.updateHeaders(headers: requestHeaders)
            requestBody = .stream(length: reader.contentSize) { writer in
                return writer.write(reader: reader, on: eventLoop)
            }
        case .empty:
            requestBody = nil
        }
        do {
            let asyncRequest = try AsyncHTTPClient.HTTPClient.Request(
                url: request.url,
                method: request.method,
                headers: requestHeaders,
                body: requestBody
            )
            return self.execute(
                request: asyncRequest,
                eventLoop: .delegate(on: eventLoop),
                deadline: .now() + timeout,
                context: context
            ).map { $0 }
        } catch {
            return eventLoopGroup.next().makeFailedFuture(error)
        }
    }

    public func execute(request: AWSHTTPRequest, timeout: TimeAmount, on eventLoop: EventLoop, context: LoggingContext, stream: @escaping ResponseStream) -> EventLoopFuture<AWSHTTPResponse> {
        let requestBody: AsyncHTTPClient.HTTPClient.Body?
        if case .byteBuffer(let body) = request.body.payload {
            requestBody = .byteBuffer(body)
        } else {
            requestBody = nil
        }
        do {
            let asyncRequest = try AsyncHTTPClient.HTTPClient.Request(
                url: request.url,
                method: request.method,
                headers: request.headers,
                body: requestBody
            )
            let delegate = AWSHTTPClientResponseDelegate(host: asyncRequest.host, stream: stream)
            return self.execute(
                request: asyncRequest,
                delegate: delegate,
                eventLoop: .delegate(on: eventLoop),
                context: context,
                deadline: .now() + timeout
            ).futureResult
        } catch {
            return eventLoopGroup.next().makeFailedFuture(error)
        }
    }
}

extension AsyncHTTPClient.HTTPClient.Response: AWSHTTPResponse {}
