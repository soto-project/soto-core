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

import NIOCore
import SotoSignerV4

private let bufferSize: Int = 64 * 1024
private let chunkSignatureLength = 1 + 16 + 64  // ";" + "chunk-signature=" + hex(sha256)
private let endOfLineLength = 2
private let bufferSizeInHex = String(bufferSize, radix: 16)
private let maxHeaderSize: Int = bufferSizeInHex.count + chunkSignatureLength + endOfLineLength

/// AsyncSequence that S3 signs the data returned from a base sequence
///
/// See https://docs.aws.amazon.com/AmazonS3/latest/API/sigv4-streaming.html for details
struct S3SignedAsyncSequence<Base: AsyncSequence & Sendable>: AsyncSequence, Sendable where Base.Element == ByteBuffer {
    typealias Element = ByteBuffer

    let base: Base
    let signer: AWSSigner
    let seedSigningData: UnsafeTransfer<AWSSigner.ChunkedSigningData>

    struct AsyncIterator: AsyncIteratorProtocol {
        enum State {
            case writeHeader
            case writeBody(ByteBuffer)
            case writeTail
            case end
        }

        var baseIterator: FixedSizeByteBufferAsyncSequence<Base>.AsyncIterator
        let signer: AWSSigner
        var signingData: AWSSigner.ChunkedSigningData
        var state: State = .writeHeader
        var count: Int = 0

        mutating func next() async throws -> ByteBuffer? {
            switch self.state {
            case .writeHeader:
                if let buffer = try await self.baseIterator.next() {
                    self.signingData = self.signer.signChunk(body: .byteBuffer(buffer), signingData: self.signingData)
                    let header = "\(String(buffer.readableBytes, radix: 16));chunk-signature=\(self.signingData.signature)\r\n"
                    self.state = .writeBody(buffer)
                    return ByteBuffer(string: header)
                } else {
                    self.signingData = self.signer.signChunk(body: .byteBuffer(ByteBuffer()), signingData: self.signingData)
                    let header = "\(String(0, radix: 16));chunk-signature=\(self.signingData.signature)\r\n\r\n"
                    self.state = .end
                    return ByteBuffer(string: header)
                }

            case .writeBody(let body):
                self.state = .writeTail
                return body

            case .writeTail:
                self.state = .writeHeader
                return ByteBuffer(string: "\r\n")

            case .end:
                return nil
            }
        }
    }

    func makeAsyncIterator() -> AsyncIterator {
        // S3 signing requires a fixed chunk size. AWS recommend 64K for the chunk size
        .init(
            baseIterator: self.base.fixedSizeSequence(chunkSize: 64 * 1024).makeAsyncIterator(),
            signer: self.signer,
            signingData: self.seedSigningData.wrappedValue
        )
    }

    /// Calculate content size for aws chunked data.
    func contentSize(from length: Int) -> Int {
        let numberOfChunks = length / bufferSize
        let remainingBytes = length - numberOfChunks * bufferSize
        let lastChunkSize: Int
        if remainingBytes > 0 {
            lastChunkSize = remainingBytes + String(remainingBytes, radix: 16).count + chunkSignatureLength + endOfLineLength * 2
        } else {
            lastChunkSize = 0
        }
        let fullSize =
            numberOfChunks * (bufferSize + maxHeaderSize + endOfLineLength)  // number of chunks * chunk size
            + lastChunkSize  // last chunk size
            + 1 + chunkSignatureLength + endOfLineLength * 2  // tail chunk size "(0;chunk-signature=hash)\r\n\r\n"
        return fullSize
    }
}

extension AsyncSequence where Element == ByteBuffer, Self: Sendable {
    /// create S3 signed sequence of data
    func s3Signed(signer: AWSSigner, seedSigningData: AWSSigner.ChunkedSigningData) -> S3SignedAsyncSequence<Self> {
        S3SignedAsyncSequence(base: self, signer: signer, seedSigningData: .init(seedSigningData))
    }
}
