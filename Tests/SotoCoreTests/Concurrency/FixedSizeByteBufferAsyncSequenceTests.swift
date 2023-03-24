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
final class FixedSizeByteBufferAsyncSequenceTests: XCTestCase {
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

    func testLargerChunkSize() async throws {
        try await self.testFixedSizeByteBufferSequence(bufferSize: 16000, generatedByteBufferSizeRange: 1..<1000, fixedChunkSize: 4096)
    }

    func testSmallerChunkSize() async throws {
        try await self.testFixedSizeByteBufferSequence(bufferSize: 16000, generatedByteBufferSizeRange: 500..<1000, fixedChunkSize: 256)
    }

    func testSimilarSizedChunkSize() async throws {
        try await self.testFixedSizeByteBufferSequence(bufferSize: 16000, generatedByteBufferSizeRange: 1..<1000, fixedChunkSize: 500)
    }

    func testBufferSizeIsMultipleOfChunkSize() async throws {
        try await self.testFixedSizeByteBufferSequence(bufferSize: 1000, generatedByteBufferSizeRange: 1..<200, fixedChunkSize: 250)
        try await self.testFixedSizeByteBufferSequence(bufferSize: 1000, generatedByteBufferSizeRange: 500..<1000, fixedChunkSize: 250)
    }

    func testBufferSizeIsEqualToChunkSize() async throws {
        try await self.testFixedSizeByteBufferSequence(bufferSize: 1000, generatedByteBufferSizeRange: 500..<1000, fixedChunkSize: 1000)
        try await self.testFixedSizeByteBufferSequence(bufferSize: 1000, generatedByteBufferSizeRange: 1000..<1001, fixedChunkSize: 1000)
    }

    func testShortSequence() async throws {
        try await self.testFixedSizeByteBufferSequence(bufferSize: 250, generatedByteBufferSizeRange: 500..<1000, fixedChunkSize: 1000)
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

#endif // compiler(>=5.5.2) && canImport(_Concurrency)
