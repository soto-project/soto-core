//===----------------------------------------------------------------------===//
//
// This source file is part of the Soto for AWS open source project
//
// Copyright (c) 2017-2021 the Soto project authors
// Licensed under Apache License v2.0
//
// See LICENSE.txt for license information
// See CONTRIBUTORS.txt for the list of Soto project authors
//
// SPDX-License-Identifier: Apache-2.0
//
//===----------------------------------------------------------------------===//

import NIO
import SotoSignerV4

class S3StreamWriter: StreamWriterProtocol {
    /// Working buffer size
    static let bufferSize: Int = 64 * 1024
    static let bufferSizeInHex = String(bufferSize, radix: 16)
    static let bufferSizeLength = bufferSizeInHex.count
    static let chunkSignatureLength = 1 + 16 + 64 // ";" + "chunk-signature=" + hex(sha256)
    static let endOfLineLength = 2
    /// Maximum size of chunk header
    static let maxHeaderSize: Int = bufferSizeInHex.count + chunkSignatureLength + endOfLineLength

    let length: Int
    var bytesWritten: Int
    let eventLoop: EventLoop
    let writerPromise: EventLoopPromise<ChildStreamWriter>
    let finishedPromise: EventLoopPromise<Void>

    /// bytebuffer allocator
    var byteBufferAllocator: ByteBufferAllocator

    var signer: AWSSigner
    var signingData: AWSSigner.ChunkedSigningData
    var headerBuffer: ByteBuffer
    var workingBuffer: ByteBuffer
    var tailBuffer: ByteBuffer

    init(
        length: Int,
        signer: AWSSigner,
        seedSigningData: AWSSigner.ChunkedSigningData,
        byteBufferAllocator: ByteBufferAllocator,
        eventLoop: EventLoop
    ) {
        self.length = Self.calculateLength(from: length)
        self.bytesWritten = 0
        self.eventLoop = eventLoop
        self.writerPromise = eventLoop.makePromise()
        self.finishedPromise = eventLoop.makePromise()

        self.signer = signer
        self.signingData = seedSigningData
        // have separate buffers so we aren't allocating 128k
        self.byteBufferAllocator = byteBufferAllocator
        self.headerBuffer = byteBufferAllocator.buffer(capacity: Self.maxHeaderSize)
        self.workingBuffer = byteBufferAllocator.buffer(capacity: Self.bufferSize)
        self.tailBuffer = byteBufferAllocator.buffer(capacity: Self.endOfLineLength)
        self.tailBuffer.writeString("\r\n")
    }

    /// Update HTTP headers. Add "content-encoding" header. The "x-amz-decoded-content-length" header is added earlier in AWSRequest when
    /// initiating the signing process
    /// - Parameter headers: headers to update
    func updateHeaders(headers: HTTPHeaders) -> HTTPHeaders {
        var headers = headers
        headers.add(name: "content-encoding", value: "aws-chunked")
        return headers
    }

    func write(_ result: StreamWriterResult, to writer: ChildStreamWriter) -> EventLoopFuture<Void> {
        switch result {
        case .byteBuffer(var buffer):
            let bytesRequired = Self.bufferSize - self.workingBuffer.readableBytes
            guard var slice = buffer.readSlice(length: bytesRequired) else {
                self.workingBuffer.writeBuffer(&buffer)
                return self.eventLoop.makeSucceededVoidFuture()
            }
            self.workingBuffer.writeBuffer(&slice)
            var writeResult = self.writeSignedBuffer(self.workingBuffer, to: writer)
            self.workingBuffer.clear()

            while var slice = buffer.readSlice(length: Self.bufferSize) {
                self.workingBuffer.writeBuffer(&slice)
                writeResult = self.writeSignedBuffer(self.workingBuffer, to: writer)
                self.workingBuffer.clear()
            }

            self.workingBuffer.writeBuffer(&buffer)
            return writeResult
        case .end:
            // if working buffer still has data write it out
            if self.workingBuffer.readableBytes > 0 {
                _ = self.writeSignedBuffer(self.workingBuffer, to: writer)
                self.workingBuffer.clear()
            }
            // write empty buffer
            _ = self.writeSignedBuffer(self.workingBuffer, to: writer)

            self.finishedPromise.succeed(())
            // write end
            return writer.write(result, on: self.eventLoop)
        }
    }

    func writeSignedBuffer(_ buffer: ByteBuffer, to writer: ChildStreamWriter) -> EventLoopFuture<Void> {
        // sign header etc
        assert(buffer.readableBytes <= Self.bufferSize)
        self.signingData = self.signer.signChunk(body: .byteBuffer(buffer), signingData: self.signingData)
        let header = "\(String(buffer.readableBytes, radix: 16));chunk-signature=\(self.signingData.signature)\r\n"
        self.headerBuffer.clear()
        self.headerBuffer.writeString(header)

        self.bytesWritten += self.headerBuffer.readableBytes + buffer.readableBytes + self.tailBuffer.readableBytes

        writer.write(.byteBuffer(self.headerBuffer), on: self.eventLoop)
        writer.write(.byteBuffer(buffer), on: self.eventLoop)
        return writer.write(.byteBuffer(self.tailBuffer), on: self.eventLoop)
    }

    /// Calculate content size for aws chunked data.
    static func calculateLength(from length: Int) -> Int {
        let numberOfChunks = length / Self.bufferSize
        let remainingBytes = length - numberOfChunks * Self.bufferSize
        let lastChunkSize: Int
        if remainingBytes > 0 {
            lastChunkSize = remainingBytes + String(remainingBytes, radix: 16).count + Self.chunkSignatureLength + Self.endOfLineLength * 2
        } else {
            lastChunkSize = 0
        }
        let fullSize = numberOfChunks * (Self.bufferSize + Self.maxHeaderSize + Self.endOfLineLength) // number of chunks * chunk size
            + lastChunkSize // last chunk size
            + 1 + Self.chunkSignatureLength + Self.endOfLineLength * 2 // tail chunk size "(0;chunk-signature=hash)\r\n\r\n"
        return fullSize
    }
}
