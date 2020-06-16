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

/// HTTP client delegate capturing the body parts received from AsyncHTTPClient.
class AWSHTTPClientResponseDelegate: HTTPClientResponseDelegate {
    typealias Response = AWSHTTPResponse
    
    enum State {
        case idle
        case head(HTTPResponseHead)
        case end
        case error(Error)
    }

    let host: String
    let stream: (ByteBuffer, EventLoop)->EventLoopFuture<Void>
    var state: State

    init(host: String, stream: @escaping (ByteBuffer, EventLoop)->EventLoopFuture<Void>) {
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
        case .end:
            preconditionFailure("request already processed")
        case .error:
            break
        }
        return task.eventLoop.makeSucceededFuture(())
    }
    
    func didReceiveBodyPart(task: HTTPClient.Task<Response>, _ part: ByteBuffer) -> EventLoopFuture<Void> {
        switch self.state {
        case .idle:
            preconditionFailure("no head received before body")
        case .head(let head):
            if (200..<300).contains(head.status.code) {
                return stream(part, task.eventLoop)
            }
            self.state = .head(head)
        case .end:
            preconditionFailure("request already processed")
        case .error:
            break
        }
        return task.eventLoop.makeSucceededFuture(())
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
        case .end:
            preconditionFailure("request already processed")
        case .error(let error):
            throw error
        }
    }
}
