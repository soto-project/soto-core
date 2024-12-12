//===----------------------------------------------------------------------===//
//
// This source file is part of the Soto for AWS open source project
//
// Copyright (c) 2017-2024 the Soto project authors
// Licensed under Apache License v2.0
//
// See LICENSE.txt for license information
// See CONTRIBUTORS.txt for the list of Soto project authors
//
// SPDX-License-Identifier: Apache-2.0
//
//===----------------------------------------------------------------------===//

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif
import Logging
import NIOCore
import NIOHTTP1

/// Storage for HTTP body which can be either a ByteBuffer or an AsyncSequence of
/// ByteBuffers
public struct AWSHTTPBody: Sendable {
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

    public init(bytes: some Collection<UInt8>, byteBufferAllocator: ByteBufferAllocator = .init()) {
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

    public init<BufferSequence: AsyncSequence & Sendable>(asyncSequence: BufferSequence, length: Int?)
    where BufferSequence.Element: Collection<UInt8> & Sendable {
        self.storage = .asyncSequence(sequence: .init(asyncSequence.map { .init(bytes: $0) }), length: length)
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

extension AWSHTTPBody: AsyncSequence {
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

extension AWSHTTPBody: AWSDecodableShape {
    public init(from decoder: Decoder) throws {
        let responseContainer = decoder.userInfo[.awsResponse]! as! ResponseDecodingContainer
        self = responseContainer.response.body
    }
}

extension AWSHTTPBody: AWSEncodableShape {
    public func encode(to encoder: Encoder) throws {
        enum CodingKeys: CodingKey {}
        _ = encoder.container(keyedBy: CodingKeys.self)
        let requestContainer = encoder.userInfo[.awsRequest]! as! RequestEncodingContainer
        requestContainer.body = self
    }
}
