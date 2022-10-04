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

import Foundation
import Logging
import NIOCore
import NIOHTTP1

/// Function that streamed response chunks are sent ot
public typealias AWSResponseStream = (ByteBuffer, EventLoop) -> EventLoopFuture<Void>

/// HTTP Request
struct AWSHTTPRequest {
    let url: URL
    let method: HTTPMethod
    let headers: HTTPHeaders
    let body: AWSPayload

    init(url: URL, method: HTTPMethod, headers: HTTPHeaders = [:], body: AWSPayload = .empty) {
        self.url = url
        self.method = method
        self.headers = headers
        self.body = body
    }
}

/// HTTP Response
protocol AWSHTTPResponse {
    /// HTTP response status
    var status: HTTPResponseStatus { get }
    /// HTTP response headers
    var headers: HTTPHeaders { get }
    /// Payload of response
    var body: ByteBuffer? { get }
}
