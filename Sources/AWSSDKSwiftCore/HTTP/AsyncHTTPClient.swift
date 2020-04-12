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
    public func execute(request: AWSHTTPRequest, timeout: TimeAmount, on eventLoop: EventLoop?) -> EventLoopFuture<AWSHTTPResponse> {
        if let eventLoop = eventLoop {
            precondition(self.eventLoopGroup.makeIterator().contains { $0 === eventLoop }, "EventLoop provided to AWSClient must be part of the HTTPClient's EventLoopGroup.")
        }        
        let eventLoop = eventLoop ?? eventLoopGroup.next()
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

    func execute(request: AWSHTTPRequest, delegate: AWSHTTPClientResponseDelegate, timeout: TimeAmount) -> Task<AWSHTTPResponse>? {
        let requestBody: AsyncHTTPClient.HTTPClient.Body?
        if let body = request.body {
            requestBody = .byteBuffer(body)
        } else {
            requestBody = nil
        }
        do {
            let asyncRequest = try AsyncHTTPClient.HTTPClient.Request(url: request.url, method: request.method, headers: request.headers, body: requestBody)
            return execute(request: asyncRequest, delegate: delegate, deadline: .now() + timeout)
        } catch {
            return nil
        }
    }
}

extension AsyncHTTPClient.HTTPClient.Response: AWSHTTPResponse {}

class AWSHTTPClientResponseDelegate: HTTPClientResponseDelegate {

    init(_ stream: @escaping (ByteBuffer)->()) {
        self.stream = stream
        self.head = nil
    }

    func didReceiveHead(task: HTTPClient.Task<AWSHTTPResponse>, _ head: HTTPResponseHead) -> EventLoopFuture<Void> {
        self.head = head
        return task.eventLoop.makeSucceededFuture(())
    }
    
    func didReceiveBodyPart(task: HTTPClient.Task<AWSHTTPResponse>, _ buffer: ByteBuffer) -> EventLoopFuture<Void> {
        stream(buffer)
        return task.eventLoop.makeSucceededFuture(())
    }

    func didFinishRequest(task: HTTPClient.Task<AWSHTTPResponse>) throws -> AWSHTTPResponse {
        return AsyncHTTPClient.HTTPClient.Response(host: "me", status: head.status, headers: head.headers, body: nil)
    }

    let stream: (ByteBuffer)->()
    var head: HTTPResponseHead!
}

