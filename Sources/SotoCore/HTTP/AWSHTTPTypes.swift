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

/// Generic HTTP Response returned from HTTP Client
struct AWSHTTPResponse: Sendable {
    /// HTTP Body (wraps any AsyncSequence returned from HTTP Client)
    struct Body: AsyncSequence {
        typealias Element = ByteBuffer
        let nextBuffer: @Sendable () -> (() async throws -> ByteBuffer?)

        /// initialize with function returning a function that returns a stream of
        /// ByteBuffers
        init(_ nextBuffer: @escaping @Sendable () -> (() async throws -> ByteBuffer?)) {
            self.nextBuffer = nextBuffer
        }

        /// initialize with empty body
        init() {
            self.init {
                return { return nil }
            }
        }

        /// initialize with AsyncSequence of ByteBuffers
        init<BufferSequence: AsyncSequence>(_ sequence: BufferSequence) where BufferSequence.Element == ByteBuffer {
            self.nextBuffer = {
                var iterator = sequence.makeAsyncIterator()
                return { try await iterator.next() }
            }
        }

        struct AsyncIterator: AsyncIteratorProtocol {
            let nextBuffer: () async throws -> ByteBuffer?

            func next() async throws -> Element? {
                try await self.nextBuffer()
            }
        }

        func makeAsyncIterator() -> AsyncIterator {
            .init(nextBuffer: self.nextBuffer())
        }
    }

    /// Initialize AWSHTTPResponse
    init(status: HTTPResponseStatus, headers: HTTPHeaders, body: Body = .init()) {
        self.status = status
        self.headers = headers
        self.body = body
    }

    /// The HTTP status for this response.
    var status: HTTPResponseStatus

    /// The HTTP headers of this response.
    var headers: HTTPHeaders

    /// The body of this HTTP response.
    var body: Body
}
