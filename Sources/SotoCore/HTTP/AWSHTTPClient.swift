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

import BaggageContext
import Foundation
import Logging
import NIO
import NIOHTTP1

/// HTTP Request
public struct AWSHTTPRequest {
    public let url: URL
    public let method: HTTPMethod
    public let headers: HTTPHeaders
    public let body: AWSPayload

    public init(url: URL, method: HTTPMethod, headers: HTTPHeaders = [:], body: AWSPayload = .empty) {
        self.url = url
        self.method = method
        self.headers = headers
        self.body = body
    }
}

/// HTTP Response
public protocol AWSHTTPResponse {
    var status: HTTPResponseStatus { get }
    var headers: HTTPHeaders { get }
    var body: ByteBuffer? { get }
}

/// Protocol defining requirements for a HTTPClient
public protocol AWSHTTPClient {
    typealias ResponseStream = (ByteBuffer, EventLoop) -> EventLoopFuture<Void>

    /// Execute HTTP request and return a future holding a HTTP Response
    func execute(request: AWSHTTPRequest, timeout: TimeAmount, on eventLoop: EventLoop, context: Context) -> EventLoopFuture<AWSHTTPResponse>

    /// Execute an HTTP request with a streamed response
    func execute(request: AWSHTTPRequest, timeout: TimeAmount, on eventLoop: EventLoop, context: Context, stream: @escaping ResponseStream) -> EventLoopFuture<AWSHTTPResponse>

    /// This should be called before an HTTP Client can be de-initialised
    func shutdown(queue: DispatchQueue, _ callback: @escaping (Error?) -> Void)

    /// Event loop group used by client
    var eventLoopGroup: EventLoopGroup { get }
}

extension AWSHTTPClient {
    /// Execute an HTTP request with a streamed response
    public func execute(request: AWSHTTPRequest, timeout: TimeAmount, on eventLoop: EventLoop, context: Context, stream: @escaping ResponseStream) -> EventLoopFuture<AWSHTTPResponse> {
        preconditionFailure("\(type(of: self)) does not support response streaming")
    }
}
