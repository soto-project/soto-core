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
public protocol AWSClientStreamable {
    
    /// Consume the data from a bytebuffer and if that is enough to generate an instance of this return the instance
    /// - Parameter byteBuffer: byte buffer to consume
    static func consume(byteBuffer: inout ByteBuffer) throws -> Self?
}

extension ByteBuffer: AWSClientStreamable {
    public static func consume(byteBuffer: inout ByteBuffer) throws -> Self? {
        let newByteBuffer = byteBuffer
        byteBuffer.moveReaderIndex(forwardBy: byteBuffer.readableBytes)
        return newByteBuffer
    }
}

/// HTTP client delegate capturing the body parts received from AsyncHTTPClient.
class AWSHTTPClientResponseDelegate<Payload: AWSClientStreamable>: HTTPClientResponseDelegate {
    typealias Response = AWSHTTPResponse
    
    enum State {
        case idle
        case head(HTTPResponseHead)
        case body(HTTPResponseHead, ByteBuffer)
        case end
        case error(Error)
    }

    let host: String
    let stream: (Payload, EventLoop)->EventLoopFuture<Void>
    var state: State

    init(host: String, stream: @escaping (Payload, EventLoop)->EventLoopFuture<Void>) {
        self.host = host
        self.stream = stream
        self.state = .idle
    }

    func didReceiveHead(task: HTTPClient.Task<Response>, _ head: HTTPResponseHead) -> EventLoopFuture<Void> {
        switch self.state {
        case .idle:
            self.state = .head(head)
        case .head:
            preconditionFailure("head already set")
        case .body:
            preconditionFailure("no head received before body")
        case .end:
            preconditionFailure("request already processed")
        case .error:
            break
        }
        return task.eventLoop.makeSucceededFuture(())
    }
    
    func didReceiveBodyPart(task: HTTPClient.Task<Response>, _ part: ByteBuffer) -> EventLoopFuture<Void> {
        do {
            switch self.state {
            case .idle:
                preconditionFailure("no head received before body")
            case .head(let head):
                var part = part
                if (200..<300).contains(head.status.code) {
                    if let payload = try Payload.consume(byteBuffer: &part) {
                        // remove read data from accumulation buffer
                        self.state = .body(head, part.slice())
                        return stream(payload, task.eventLoop)
                    }
                }
                self.state = .body(head, part)
            case .body(let head, var body):
                if body.readableBytes > 0 {
                    var part = part
                    body.writeBuffer(&part)
                } else {
                    body = part
                }
                if (200..<300).contains(head.status.code) {
                    if let payload = try Payload.consume(byteBuffer: &body) {
                        // remove read data from accumulation buffer
                        self.state = .body(head, body.slice())
                        return stream(payload, task.eventLoop)
                    }
                }
                self.state = .body(head, body)
            case .end:
                preconditionFailure("request already processed")
            case .error:
                break
            }
            return task.eventLoop.makeSucceededFuture(())
        } catch {
            return task.eventLoop.makeFailedFuture(error)
        }
    }

    func didReceiveError(task: HTTPClient.Task<Response>, _ error: Error) {
        self.state = .error(error)
    }

    func didFinishRequest(task: HTTPClient.Task<Response>) throws -> AWSHTTPResponse {
        switch self.state {
        case .idle:
            preconditionFailure("no head received before end")
        case .head(let head):
            return AsyncHTTPClient.HTTPClient.Response(host: host, status: head.status, headers: head.headers, body: nil)
        case .body(let head, let body):
            if (200..<300).contains(head.status.code) {
                return AsyncHTTPClient.HTTPClient.Response(host: host, status: head.status, headers: head.headers, body: nil)
            } else {
                return AsyncHTTPClient.HTTPClient.Response(host: host, status: head.status, headers: head.headers, body: body)
            }
        case .end:
            preconditionFailure("request already processed")
        case .error(let error):
            throw error
        }
    }
}

/// extend to include delegate support
extension AsyncHTTPClient.HTTPClient {
    public func execute<Payload: AWSClientStreamable>(request: AWSHTTPRequest, timeout: TimeAmount, on eventLoop: EventLoop?, stream: @escaping (Payload, EventLoop)->EventLoopFuture<Void>) -> EventLoopFuture<AWSHTTPResponse> {
        let requestBody: AsyncHTTPClient.HTTPClient.Body?
        if let body = request.body {
            requestBody = .byteBuffer(body)
        } else {
            requestBody = nil
        }
        do {
            let asyncRequest = try AsyncHTTPClient.HTTPClient.Request(url: request.url, method: request.method, headers: request.headers, body: requestBody)
            let delegate = AWSHTTPClientResponseDelegate(host: asyncRequest.host, stream: stream)
            return execute(request: asyncRequest, delegate: delegate, deadline: .now() + timeout).futureResult
        } catch {
            return eventLoopGroup.next().makeFailedFuture(error)
        }
    }
}

