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

import AsyncHTTPClient
import Logging
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
    public func execute(request: AWSHTTPRequest, timeout: TimeAmount, on eventLoop: EventLoop, logger: Logger) -> EventLoopFuture<AWSHTTPResponse> {
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
            let asyncRequest = try AsyncHTTPClient.HTTPClient.Request(url: request.url, method: request.method, headers: requestHeaders, body: requestBody)
            return execute(request: asyncRequest, eventLoop: .delegate(on: eventLoop), deadline: .now() + timeout).map { $0 }
        } catch {
            return eventLoopGroup.next().makeFailedFuture(error)
        }
    }
}

/// extend to include response streaming support
extension AsyncHTTPClient.HTTPClient {
    public func execute(request: AWSHTTPRequest, timeout: TimeAmount, on eventLoop: EventLoop, logger: Logger, stream: @escaping ResponseStream) -> EventLoopFuture<AWSHTTPResponse> {
        let requestBody: AsyncHTTPClient.HTTPClient.Body?
        if case .byteBuffer(let body) = request.body.payload {
            requestBody = .byteBuffer(body)
        } else {
            requestBody = nil
        }
        do {
            let asyncRequest = try AsyncHTTPClient.HTTPClient.Request(url: request.url, method: request.method, headers: request.headers, body: requestBody)
            let delegate = AWSHTTPClientResponseDelegate(host: asyncRequest.host, stream: stream)
            return execute(request: asyncRequest, delegate: delegate, eventLoop: .delegate(on: eventLoop), deadline: .now() + timeout)
                .futureResult
                // temporarily wait on delegate response finishing while AHC does not do this for us. See https://github.com/swift-server/async-http-client/issues/274
                .flatMap { response in
                    // if delegate future 
                    guard let futureResult = delegate.bodyPartFuture else { return eventLoop.makeSucceededFuture(response)}
                    return futureResult.map { return response }
            }
        } catch {
            return eventLoopGroup.next().makeFailedFuture(error)
        }
    }
}


extension AsyncHTTPClient.HTTPClient.Response: AWSHTTPResponse {}

