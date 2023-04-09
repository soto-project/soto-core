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

#if compiler(>=5.5.2) && canImport(_Concurrency)

import NIOCore
import SotoCore
import SotoTestUtils
import XCTest

@available(macOS 10.15, iOS 13.0, tvOS 13.0, watchOS 6.0, *)
final class AsyncSequenceTests: XCTestCase {
    func testFixedSizeByteBufferSequence(
        bufferSize: Int,
        generatedByteBufferSizeRange: Range<Int>,
        fixedChunkSize: Int
    ) async throws {
        let bytes = createRandomBuffer(23, 4, size: bufferSize)
        let buffer = ByteBufferAllocator().buffer(bytes: bytes)
        let seq = TestByteBufferSequence(source: buffer, range: generatedByteBufferSizeRange)
        let chunkedSequence = seq.fixedSizeSequence(chunkSize: fixedChunkSize)
        var result = ByteBufferAllocator().buffer(capacity: bufferSize)
        var prevChunk: ByteBuffer?
        for try await chunk in chunkedSequence {
            // doing this so I don't check the length of the last chunk
            if let prevChunk = prevChunk {
                XCTAssertEqual(prevChunk.readableBytes, fixedChunkSize)
            }
            result.writeImmutableBuffer(chunk)
            prevChunk = chunk
        }
        XCTAssertEqual(buffer, result)
    }

    func testFixedSizeByteBufferLargerChunkSize() async throws {
        try await self.testFixedSizeByteBufferSequence(bufferSize: 16000, generatedByteBufferSizeRange: 1..<1000, fixedChunkSize: 4096)
    }

    func testFixedSizeByteBufferSmallerChunkSize() async throws {
        try await self.testFixedSizeByteBufferSequence(bufferSize: 16000, generatedByteBufferSizeRange: 500..<1000, fixedChunkSize: 256)
    }

    func testFixedSizeByteBufferSimilarSizedChunkSize() async throws {
        try await self.testFixedSizeByteBufferSequence(bufferSize: 16000, generatedByteBufferSizeRange: 1..<1000, fixedChunkSize: 500)
    }

    func testFixedSizeByteBufferBufferSizeIsMultipleOfChunkSize() async throws {
        try await self.testFixedSizeByteBufferSequence(bufferSize: 1000, generatedByteBufferSizeRange: 1..<200, fixedChunkSize: 250)
        try await self.testFixedSizeByteBufferSequence(bufferSize: 1000, generatedByteBufferSizeRange: 500..<1000, fixedChunkSize: 250)
    }

    func testFixedSizeByteBufferBufferSizeIsEqualToChunkSize() async throws {
        try await self.testFixedSizeByteBufferSequence(bufferSize: 1000, generatedByteBufferSizeRange: 500..<1000, fixedChunkSize: 1000)
        try await self.testFixedSizeByteBufferSequence(bufferSize: 1000, generatedByteBufferSizeRange: 1000..<1001, fixedChunkSize: 1000)
    }

    func testFixedSizeByteBufferShortSequence() async throws {
        try await self.testFixedSizeByteBufferSequence(bufferSize: 250, generatedByteBufferSizeRange: 500..<1000, fixedChunkSize: 1000)
    }

    func testEnumeratedSequence() async throws {
        let sequence = [24, 23, 300]
        let asyncSequence = sequence.asyncSequence
        let result: [(Int, Int)] = try await asyncSequence.enumerated().collect()
        XCTAssertEqual(result.map { $0.0 }, [0, 1, 2])
        XCTAssertEqual(result.map { $0.1 }, sequence)
    }
}

@available(macOS 10.15, iOS 13.0, tvOS 13.0, watchOS 6.0, *)
struct TestByteBufferSequence: AsyncSequence {
    typealias Element = ByteBuffer
    let source: ByteBuffer
    let range: Range<Int>

    struct AsyncIterator: AsyncIteratorProtocol {
        var source: ByteBuffer
        var range: Range<Int>

        mutating func next() async throws -> ByteBuffer? {
            let size = Swift.min(Int.random(in: self.range), self.source.readableBytes)
            if size == 0 {
                return nil
            } else {
                return self.source.readSlice(length: size)
            }
        }
    }

    /// Make async iterator
    public func makeAsyncIterator() -> AsyncIterator {
        return AsyncIterator(source: self.source, range: self.range)
    }
}

/// create AsyncSequence from Sequence
@available(macOS 10.15, iOS 13.0, tvOS 13.0, watchOS 6.0, *)
extension Sequence {
    var asyncSequence: SequenceAsyncSequence<Self> { .init(base: self) }
}

@available(macOS 10.15, iOS 13.0, tvOS 13.0, watchOS 6.0, *)
struct SequenceAsyncSequence<Base: Sequence>: AsyncSequence {
    typealias Element = Base.Element
    let base: Base
    public struct AsyncIterator: AsyncIteratorProtocol {
        var iterator: Base.Iterator

        public mutating func next() async throws -> Element? {
            return self.iterator.next()
        }
    }

    /// Make async iterator
    public func makeAsyncIterator() -> AsyncIterator {
        return AsyncIterator(iterator: self.base.makeIterator())
    }
}

/// Collect output of AsyncSequence into an Array
@available(macOS 10.15, iOS 13.0, tvOS 13.0, watchOS 6.0, *)
extension AsyncSequence {
    func collect() async rethrows -> [Element] {
        var result: [Element] = []
        for try await element in self {
            result.append(element)
        }
        return result
    }
}

#endif // compiler(>=5.5.2) && canImport(_Concurrency)
