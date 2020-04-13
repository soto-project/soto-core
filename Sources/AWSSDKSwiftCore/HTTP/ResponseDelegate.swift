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
import Foundation
import NIO
import NIOHTTP1

/// Protocol defining an object that can be streamed by aws-sdk-swift. It is required to be initialize copies of itself from byte buffers
public protocol AWSHTTPClientStreamable {
    static func consume(byteBuffer: ByteBuffer) throws -> Self?
}

extension ByteBuffer: AWSHTTPClientStreamable {
    public static func consume(byteBuffer: ByteBuffer) throws -> Self? { return byteBuffer }
}

/// HTTP client delegate capturing the body parts received from AsyncHTTPClient.
class AWSHTTPClientResponseDelegate<Payload: AWSHTTPClientStreamable>: HTTPClientResponseDelegate {

    init(host: String, stream: @escaping (Payload, EventLoop)->EventLoopFuture<Void>) {
        self.host = host
        self.stream = stream
        self.head = nil
    }

    func didReceiveHead(task: HTTPClient.Task<AWSHTTPResponse>, _ head: HTTPResponseHead) -> EventLoopFuture<Void> {
        self.head = head
        return task.eventLoop.makeSucceededFuture(())
    }
    
    func didReceiveBodyPart(task: HTTPClient.Task<AWSHTTPResponse>, _ buffer: ByteBuffer) -> EventLoopFuture<Void> {
        do {
            if let payload = try Payload.consume(byteBuffer: buffer) {
                return stream(payload, task.eventLoop)
            }
            return task.eventLoop.makeSucceededFuture(())
        } catch {
            return task.eventLoop.makeFailedFuture(error)
        }
    }

    func didFinishRequest(task: HTTPClient.Task<AWSHTTPResponse>) throws -> AWSHTTPResponse {
        return AsyncHTTPClient.HTTPClient.Response(host: host, status: head.status, headers: head.headers, body: nil)
    }

    let host: String
    let stream: (Payload, EventLoop)->EventLoopFuture<Void>
    var head: HTTPResponseHead!
}

/// extend to include delegate support
extension AsyncHTTPClient.HTTPClient {
    func execute<Payload: AWSHTTPClientStreamable>(request: AWSHTTPRequest, stream: @escaping (Payload, EventLoop)->EventLoopFuture<Void>, timeout: TimeAmount) -> Task<AWSHTTPResponse>? {
        let requestBody: AsyncHTTPClient.HTTPClient.Body?
        if let body = request.body {
            requestBody = .byteBuffer(body)
        } else {
            requestBody = nil
        }
        do {
            let asyncRequest = try AsyncHTTPClient.HTTPClient.Request(url: request.url, method: request.method, headers: request.headers, body: requestBody)
            let delegate = AWSHTTPClientResponseDelegate(host: asyncRequest.host, stream: stream)
            return execute(request: asyncRequest, delegate: delegate, deadline: .now() + timeout)
        } catch {
            return nil
        }
    }
}

