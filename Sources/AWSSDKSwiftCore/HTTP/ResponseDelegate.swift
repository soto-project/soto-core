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
    
    /// Consume the data from a bytebuffer and if that is enough to generate an instance of this return the instance
    /// - Parameter byteBuffer: byte buffer to consume
    static func consume(byteBuffer: inout ByteBuffer) throws -> Self?
}

extension ByteBuffer: AWSHTTPClientStreamable {
    public static func consume(byteBuffer: inout ByteBuffer) throws -> Self? {
        let newByteBuffer = byteBuffer
        byteBuffer.moveReaderIndex(forwardBy: byteBuffer.readableBytes)
        return newByteBuffer
    }
}

/// HTTP client delegate capturing the body parts received from AsyncHTTPClient.
class AWSHTTPClientResponseDelegate<Payload: AWSHTTPClientStreamable>: HTTPClientResponseDelegate {
    typealias Response = AWSHTTPResponse
    
    init(host: String, stream: @escaping (Payload, EventLoop)->EventLoopFuture<Void>) {
        self.host = host
        self.stream = stream
        self.head = nil
        self.error = nil
        self.accumulationBuffer = ByteBufferAllocator().buffer(capacity: 0)
    }

    func didReceiveHead(task: HTTPClient.Task<Response>, _ head: HTTPResponseHead) -> EventLoopFuture<Void> {
        self.head = head
        return task.eventLoop.makeSucceededFuture(())
    }
    
    func didReceiveBodyPart(task: HTTPClient.Task<Response>, _ buffer: ByteBuffer) -> EventLoopFuture<Void> {
        do {
            // if the accumulation buffer has bytes in it then write this buffer into it
            if accumulationBuffer.readableBytes > 0 {
                var buffer = buffer
                accumulationBuffer.writeBuffer(&buffer)
            } else {
                accumulationBuffer = buffer
            }
            if (200..<300).contains(head.status.code) {
                if let payload = try Payload.consume(byteBuffer: &accumulationBuffer) {
                    // remove read data from accumulation buffer
                    self.accumulationBuffer = accumulationBuffer.slice()
                    return stream(payload, task.eventLoop)
                }
            }
            return task.eventLoop.makeSucceededFuture(())
        } catch {
            return task.eventLoop.makeFailedFuture(error)
        }
    }

    func didReceiveError(task: HTTPClient.Task<Response>, _ error: Error) {
        self.error = error
    }

    func didFinishRequest(task: HTTPClient.Task<Response>) throws -> AWSHTTPResponse {
        if let error = self.error {
            throw error
        }
        if (200..<300).contains(head.status.code) {
            return AsyncHTTPClient.HTTPClient.Response(host: host, status: head.status, headers: head.headers, body: nil)
        } else {
            return AsyncHTTPClient.HTTPClient.Response(host: host, status: head.status, headers: head.headers, body: accumulationBuffer)
        }
    }

    let host: String
    let stream: (Payload, EventLoop)->EventLoopFuture<Void>
    var error: Error?
    var head: HTTPResponseHead!
    var accumulationBuffer: ByteBuffer
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

