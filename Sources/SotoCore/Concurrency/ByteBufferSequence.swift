//===----------------------------------------------------------------------===//
//
// This source file is part of the Soto for AWS open source project
//
// Copyright (c) 2017-2023 the Soto project authors
// Licensed under Apache License v2.0
//
// See LICENSE.txt for license information
// See CONTRIBUTORS.txt for the list of Soto project authors
//
// SPDX-License-Identifier: Apache-2.0
//
//===----------------------------------------------------------------------===//

import NIOCore
import NIOPosix

/// Provide ByteBuffer as an AsyncSequence of equal size blocks
public struct ByteBufferAsyncSequence: AsyncSequence, Sendable {
    public typealias Element = ByteBuffer

    @usableFromInline
    let byteBuffer: ByteBuffer
    @usableFromInline
    let chunkSize: Int

    @inlinable
    init(
        _ byteBuffer: ByteBuffer,
        chunkSize: Int
    ) {
        self.byteBuffer = byteBuffer
        self.chunkSize = chunkSize
    }

    public struct AsyncIterator: AsyncIteratorProtocol {
        @usableFromInline
        var byteBuffer: ByteBuffer
        @usableFromInline
        let chunkSize: Int

        @inlinable
        internal init(byteBuffer: ByteBuffer, chunkSize: Int) {
            self.byteBuffer = byteBuffer
            self.chunkSize = chunkSize
        }

        @inlinable
        public mutating func next() async throws -> ByteBuffer? {
            let size = Swift.min(self.chunkSize, self.byteBuffer.readableBytes)
            if size > 0 {
                return self.byteBuffer.readSlice(length: size)
            }
            return nil
        }
    }

    @inlinable
    public func makeAsyncIterator() -> AsyncIterator {
        .init(byteBuffer: self.byteBuffer, chunkSize: self.chunkSize)
    }
}

extension ByteBuffer {
    @inlinable
    public func asyncSequence(chunkSize: Int) -> ByteBufferAsyncSequence {
        ByteBufferAsyncSequence(self, chunkSize: chunkSize)
    }
}
