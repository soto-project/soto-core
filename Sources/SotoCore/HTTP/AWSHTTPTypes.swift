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

/// Storage for HTTP body which can be either a ByteBuffer or an AsyncSequence of
/// ByteBuffers
struct HTTPBody {
    enum Storage {
        case byteBuffer(ByteBuffer)
        case asyncSequence(sequence: AnyAsyncSequence<ByteBuffer>, length: Int?)
    }

    let storage: Storage

    init() {
        self.storage = .byteBuffer(ByteBuffer())
    }

    init(_ byteBuffer: ByteBuffer) {
        self.storage = .byteBuffer(byteBuffer)
    }

    init<BufferSequence: AsyncSequence>(_ sequence: BufferSequence, length: Int?) where BufferSequence.Element == ByteBuffer {
        self.storage = .asyncSequence(sequence: .init(sequence), length: length)
    }

    func collect(upTo length: Int) async throws -> ByteBuffer {
        switch self.storage {
        case .byteBuffer(let buffer):
            return buffer
        case .asyncSequence(let sequence, _):
            return try await sequence.collect(upTo: length)
        }
    }

    var length: Int? {
        switch self.storage {
        case .byteBuffer(let buffer):
            return buffer.readableBytes
        case .asyncSequence(_, let length):
            return length
        }
    }

    var isStreaming: Bool {
        if case .asyncSequence = self.storage {
            return true
        }
        return false
    }
}

extension HTTPBody: AsyncSequence {
    typealias Element = ByteBuffer
    typealias AsyncIterator = AnyAsyncSequence<ByteBuffer>.AsyncIterator

    func makeAsyncIterator() -> AsyncIterator {
        switch self.storage {
        case .byteBuffer(let buffer):
            return AnyAsyncSequence(buffer.asyncSequence(chunkSize: buffer.readableBytes)).makeAsyncIterator()
        case .asyncSequence(let sequence, _):
            return sequence.makeAsyncIterator()
        }
    }
}

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
    /// Initialize AWSHTTPResponse
    init(status: HTTPResponseStatus, headers: HTTPHeaders, body: HTTPBody = .init()) {
        self.status = status
        self.headers = headers
        self.body = body
    }

    /// The HTTP status for this response.
    var status: HTTPResponseStatus

    /// The HTTP headers of this response.
    var headers: HTTPHeaders

    /// The body of this HTTP response.
    var body: HTTPBody
}
