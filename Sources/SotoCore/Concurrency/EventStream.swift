//===----------------------------------------------------------------------===//
//
// This source file is part of the Soto for AWS open source project
//
// Copyright (c) 2023 the Soto project authors
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
import NIOCore

/// AsyncSequence of Event stream events
public struct AWSEventStream<Event: Sendable>: Sendable {
    let base: AnyAsyncSequence<ByteBuffer>

    /// Initialise AWSEventStream from an AsyncSequence of ByteBuffers
    init<BaseSequence: AsyncSequence & Sendable>(_ base: BaseSequence) where BaseSequence.Element == ByteBuffer {
        self.base = .init(base)
    }
}

extension AWSEventStream: Decodable where Event: Decodable {
    public init(from decoder: Decoder) throws {
        let responseContainer = decoder.userInfo[.awsResponse]! as! ResponseDecodingContainer
        self.init(responseContainer.response.body)
    }
}

extension AWSEventStream: Encodable where Event: Encodable {
    public func encode(to encoder: Encoder) throws {
        preconditionFailure("Encoding EventStreams is unsupported")
    }
}

/// If Event is decodable then conform AWSEventStream to AsyncSequence
extension AWSEventStream: AsyncSequence where Event: Decodable {
    public typealias Element = Event

    public struct AsyncIterator: AsyncIteratorProtocol {
        enum State {
            case idle
            case remainingBuffer(ByteBuffer)
        }

        var baseIterator: AnyAsyncSequence<ByteBuffer>.AsyncIterator
        var state: State = .idle

        public mutating func next() async throws -> Event? {
            var accumulatedBuffer: ByteBuffer? = nil
            var buffer: ByteBuffer?
            // get buffer either from what is remaining from last buffer or a new buffer from
            // the ByteBuffer sequence
            switch self.state {
            case .idle:
                buffer = try await self.baseIterator.next()
            case .remainingBuffer(let remainingBuffer):
                buffer = remainingBuffer
            }
            while var validBuffer = buffer {
                // have we already accumulated some buffer, if so append new buffer onto the end
                if var validAccumulatedBuffer = accumulatedBuffer {
                    validAccumulatedBuffer.writeBuffer(&validBuffer)
                    validBuffer = validAccumulatedBuffer
                    accumulatedBuffer = validAccumulatedBuffer
                } else {
                    accumulatedBuffer = validBuffer
                }

                if let event = try readEvent(&validBuffer) {
                    if validBuffer.readableBytes > 0 {
                        self.state = .remainingBuffer(validBuffer)
                    } else {
                        self.state = .idle
                    }
                    return event
                }
                buffer = try await self.baseIterator.next()
            }

            return nil
        }

        /// Read event from buffer
        func readEvent(_ buffer: inout ByteBuffer) throws -> Event? {
            do {
                let event = try EventStreamDecoder().decode(Event.self, from: &buffer)
                return event
            } catch InternalAWSEventStreamError.needMoreData {
                return nil
            }
        }
    }

    public func makeAsyncIterator() -> AsyncIterator {
        .init(baseIterator: self.base.makeAsyncIterator())
    }
}
