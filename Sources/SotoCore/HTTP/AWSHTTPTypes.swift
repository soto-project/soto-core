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

/// Storage for HTTP body which can be either a ByteBuffer or an AsyncSequence of
/// ByteBuffers
public struct HTTPBody: Sendable {
    enum Storage {
        case byteBuffer(ByteBuffer)
        case asyncSequence(sequence: AnyAsyncSequence<ByteBuffer>, length: Int?)
    }

    let storage: Storage

    public init() {
        self.storage = .byteBuffer(ByteBuffer())
    }

    public init(buffer: ByteBuffer) {
        self.storage = .byteBuffer(buffer)
    }

    public init<C: Collection>(bytes: C, byteBufferAllocator: ByteBufferAllocator = .init()) where C.Element == UInt8 {
        var byteBuffer = byteBufferAllocator.buffer(capacity: bytes.count)
        byteBuffer.writeBytes(bytes)
        self.storage = .byteBuffer(byteBuffer)
    }

    public init(string: String, byteBufferAllocator: ByteBufferAllocator = .init()) {
        var byteBuffer = byteBufferAllocator.buffer(capacity: string.utf8.count)
        byteBuffer.writeString(string)
        self.storage = .byteBuffer(byteBuffer)
    }

    public init<BufferSequence: AsyncSequence & Sendable>(asyncSequence: BufferSequence, length: Int?) where BufferSequence.Element == ByteBuffer {
        self.storage = .asyncSequence(sequence: .init(asyncSequence), length: length)
    }

    public func collect(upTo length: Int) async throws -> ByteBuffer {
        switch self.storage {
        case .byteBuffer(let buffer):
            return buffer
        case .asyncSequence(let sequence, _):
            return try await sequence.collect(upTo: length)
        }
    }

    public var length: Int? {
        switch self.storage {
        case .byteBuffer(let buffer):
            return buffer.readableBytes
        case .asyncSequence(_, let length):
            return length
        }
    }

    public var isStreaming: Bool {
        switch self.storage {
        case .byteBuffer:
            return false
        case .asyncSequence:
            return true
        }
    }
}

extension HTTPBody: AsyncSequence {
    public typealias Element = ByteBuffer
    public typealias AsyncIterator = AnyAsyncSequence<ByteBuffer>.AsyncIterator

    public func makeAsyncIterator() -> AsyncIterator {
        switch self.storage {
        case .byteBuffer(let buffer):
            return AnyAsyncSequence(buffer.asyncSequence(chunkSize: buffer.readableBytes)).makeAsyncIterator()
        case .asyncSequence(let sequence, _):
            return sequence.makeAsyncIterator()
        }
    }
}

extension HTTPBody: Decodable {
    // HTTPBody has to conform to Decodable so I can add it to AWSShape objects (which conform to Decodable). But we don't want the
    // Encoder/Decoder ever to process a AWSPayload
    public init(from decoder: Decoder) throws {
        preconditionFailure("Cannot decode an HTTPBody")
    }
}

/// HTTP Request
struct AWSHTTPRequest {
    let url: URL
    let method: HTTPMethod
    let headers: HTTPHeaders
    let body: HTTPBody

    init(url: URL, method: HTTPMethod, headers: HTTPHeaders = [:], body: HTTPBody = .init()) {
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
