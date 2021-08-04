//===----------------------------------------------------------------------===//
//
// This source file is part of the Soto for AWS open source project
//
// Copyright (c) 2017-2020 the Soto project authors
// Licensed under Apache License v2.0
//
// See LICENSE.txt for license information
// See CONTRIBUTORS.txt for the list of Soto project authors
//
// SPDX-License-Identifier: Apache-2.0
//
//===----------------------------------------------------------------------===//

import NIO
import NIOHTTP1
import SotoSignerV4

/// S3 Chunked signed streamer. See https://docs.aws.amazon.com/AmazonS3/latest/API/sigv4-streaming.html
/// for more details.
class S3ChunkedStreamReader: StreamReader {
    /// Working buffer size
    static let bufferSize: Int = 64 * 1024
    static let bufferSizeInHex = String(bufferSize, radix: 16)
    static let bufferSizeLength = bufferSizeInHex.count
    static let chunkSignatureLength = 1 + 16 + 64 // ";" + "chunk-signature=" + hex(sha256)
    static let endOfLineLength = 2
    /// Maximum size of chunk header
    static let maxHeaderSize: Int = bufferSizeInHex.count + chunkSignatureLength + endOfLineLength

    /// Initialise a S3ChunkedStreamReader
    init(
        size: Int,
        seedSigningData: AWSSigner.ChunkedSigningData,
        signer: AWSSigner,
        byteBufferAllocator: ByteBufferAllocator,
        read: @escaping (EventLoop) -> EventLoopFuture<StreamReaderResult>
    ) {
        self.size = size
        self.bytesLeftToRead = size
        self.read = read
        self.signer = signer
        self.signingData = seedSigningData
        // have separate buffers so we aren't allocating 128k
        self.byteBufferAllocator = byteBufferAllocator
        self.headerBuffer = byteBufferAllocator.buffer(capacity: Self.maxHeaderSize)
        self.workingBuffer = byteBufferAllocator.buffer(capacity: Self.bufferSize)
        self.tailBuffer = byteBufferAllocator.buffer(capacity: Self.endOfLineLength)
        self.tailBuffer.writeString("\r\n")
        self.previouslyReadBuffer = nil
    }

    /// Update HTTP headers. Add "Content-encoding" header. The "x-amz-decoded-content-length" header is added earlier in AWSRequest when
    /// initiating the signing process
    /// - Parameter headers: headers to update
    func updateHeaders(headers: HTTPHeaders) -> HTTPHeaders {
        var headers = headers
        headers.add(name: "Content-Encoding", value: "aws-chunked")
        return headers
    }

    /// Fill working buffer with data supplied. First verify there isnt data left over from previous call, then keep calling `read`
    /// until the working buffer is full
    /// - Parameter eventLoop: EventLoop to work off
    /// - Returns: Full working buffer
    func fillWorkingBuffer(on eventLoop: EventLoop) -> EventLoopFuture<ByteBuffer> {
        self.workingBuffer.clear()
        // if there is still data available from the previously read buffer then use that
        if var readBuffer = previouslyReadBuffer, readBuffer.readableBytes > 0 {
            let bytesToRead = min(Self.bufferSize, readBuffer.readableBytes)
            var slice = readBuffer.readSlice(length: bytesToRead)!
            if readBuffer.readableBytes == 0 {
                self.previouslyReadBuffer = nil
            } else {
                self.previouslyReadBuffer = readBuffer
            }
            self.workingBuffer.writeBuffer(&slice)
            // if working buffer is full return the buffer
            if self.workingBuffer.readableBytes == Self.bufferSize {
                return eventLoop.makeSucceededFuture(self.workingBuffer)
            }
        }
        // if there are no bytes left to read then return with what is in the working buffer
        if self.bytesLeftToRead == 0 {
            return eventLoop.makeSucceededFuture(self.workingBuffer)
        }
        let promise: EventLoopPromise<ByteBuffer> = eventLoop.makePromise()
        func _fillBuffer() {
            self.read(eventLoop).map { result -> Void in
                // check if a byte buffer was returned. If not then it must have been `.end`
                guard case .byteBuffer(var buffer) = result else {
                    if self.bytesLeftToRead == self.workingBuffer.readableBytes {
                        promise.succeed(self.workingBuffer)
                    } else {
                        promise.fail(AWSClient.ClientError.notEnoughData)
                    }
                    return
                }
                self.bytesLeftToRead -= buffer.readableBytes

                guard self.bytesLeftToRead >= 0 else {
                    promise.fail(AWSClient.ClientError.tooMuchData)
                    return
                }
                // if working buffer is empty and this buffer is the chunk buffer size or there is no data
                // left to read and this buffer is less than the size of the chunk buffer then just return
                // this buffer. This allows us to avoid the buffer copy
                if self.workingBuffer.readableBytes == 0 {
                    if buffer.readableBytes == Self.bufferSize || (self.bytesLeftToRead == 0 && buffer.readableBytes < Self.bufferSize) {
                        promise.succeed(buffer)
                        return
                    }
                }
                let bytesRequired = Self.bufferSize - self.workingBuffer.readableBytes
                let bytesToRead = min(buffer.readableBytes, bytesRequired)
                var slice = buffer.readSlice(length: bytesToRead)!
                self.workingBuffer.writeBuffer(&slice)
                // if working buffer is full then call succeed on the promise
                if self.workingBuffer.readableBytes == Self.bufferSize {
                    // if the supplied buffer still has readable bytes then store this buffer so those bytes can
                    // be used in the next call to `fillWorkingBuffer`.
                    if buffer.readableBytes > 0 {
                        buffer.discardReadBytes()
                        self.previouslyReadBuffer = buffer
                    }
                    promise.succeed(self.workingBuffer)
                    return
                }
                // if there are still bytes left to read then call _fillBuffer again, otherwise succeed with the
                // contents of the working buffer
                if self.bytesLeftToRead > 0 {
                    _fillBuffer()
                } else {
                    promise.succeed(self.workingBuffer)
                }
            }.cascadeFailure(to: promise)
        }

        _fillBuffer()

        return promise.futureResult
    }

    /// Provide a list of `ByteBuffers` to `StreamWriter`. This function fills the working buffer and then signs it
    /// and returns it along with `ByteBuffers` that contain the header and tail data.
    ///
    /// Given the content size that we have said are going to provide this will get called once after everything has been
    /// streamed. This last time we will return an empty chunk. If the `read` function returns a byte buffer with
    ///
    /// - Parameter eventLoop: EventLoop to run everythin off
    func streamChunks(on eventLoop: EventLoop) -> EventLoopFuture<[ByteBuffer]> {
        return self.fillWorkingBuffer(on: eventLoop).map { buffer in
            // sign header etc
            assert(buffer.readableBytes <= Self.bufferSize)
            self.signingData = self.signer.signChunk(body: .byteBuffer(buffer), signingData: self.signingData)
            let header = "\(String(buffer.readableBytes, radix: 16));chunk-signature=\(self.signingData.signature)\r\n"
            self.headerBuffer.clear()
            self.headerBuffer.writeString(header)

            return [self.headerBuffer, buffer, self.tailBuffer]
        }
    }

    /// Calculate content size for aws chunked data.
    var contentSize: Int? {
        let size = self.size!
        let numberOfChunks = size / Self.bufferSize
        let remainingBytes = size - numberOfChunks * Self.bufferSize
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

    /// size of data to be streamed
    let size: Int?
    /// function providing data to be streamed
    let read: (EventLoop) -> EventLoopFuture<StreamReaderResult>
    /// bytebuffer allocator
    var byteBufferAllocator: ByteBufferAllocator

    var signer: AWSSigner
    var signingData: AWSSigner.ChunkedSigningData
    var previouslyReadBuffer: ByteBuffer?
    var headerBuffer: ByteBuffer
    var workingBuffer: ByteBuffer
    var tailBuffer: ByteBuffer
    /// bytes left to read from `read` function
    var bytesLeftToRead: Int
}
