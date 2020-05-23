//===----------------------------------------------------------------------===//
//
// This source file is part of the AWSSDKSwift open source project
//
// Copyright (c) 2017-2020 the AWSSDKSwift project authors
// Licensed under Apache License v2.0
//
// See LICENSE.txt for license information
// See CONTRIBUTORS.txt for the list of AWSSDKSwift project authors
//
// SPDX-License-Identifier: Apache-2.0
//
//===----------------------------------------------------------------------===//

import AsyncHTTPClient
import AWSSignerV4
import NIO
import NIOHTTP1

protocol StreamReader {
    
    /// size of data to be streamed
    var size: Int? { get }
    /// total size of data to be streamed plus any chunk headers
    var contentSize: Int? { get }
    /// function providing data to be streamed
    var read: (EventLoop)->EventLoopFuture<ByteBuffer> { get }
    
    func updateHeaders(headers: HTTPHeaders) -> HTTPHeaders
    func streamChunks(on eventLoop: EventLoop) -> EventLoopFuture<[ByteBuffer]>
    func endChunk() -> ByteBuffer?
}

/// Standard chunked streamer. Adds transfer-encoding : chunked header if a size is not supplied. NIO adds all the chunk headers
struct ChunkedStreamReader: StreamReader {
    func updateHeaders(headers: HTTPHeaders) -> HTTPHeaders {
        var headers = headers
        // add "Transfer-Encoding" header if streaming with unknown size
        if size == nil {
            headers.add(name: "Transfer-Encoding", value: "chunked")
        }
        return headers
    }
    
    func streamChunks(on eventLoop: EventLoop) -> EventLoopFuture<[ByteBuffer]> {
        return read(eventLoop).map { (byteBuffer) -> [ByteBuffer] in
            if byteBuffer.readableBytes > 0 {
                return [byteBuffer]
            } else {
                return []
            }
        }
    }
    
    func endChunk() -> ByteBuffer? {
        return nil
    }

    var contentSize: Int? { return size }
    
    let size: Int?
    let read: (EventLoop)->EventLoopFuture<ByteBuffer>
}

/// AWS Chunked streamer
class AWSChunkedStreamReader: StreamReader {
    static let bufferSize: Int = 64*1024
    static let bufferSizeInHex: String = String(bufferSize, radix: 16)
    static let bufferSizeLength = bufferSizeInHex.count
    static let chunkSignatureLength = 1 + 16 + 64 // ";" + "chunk-signature=" + hex(sha256)
    static let endOfLineLength = 2
    static let maxHeaderSize: Int = bufferSizeInHex.count + chunkSignatureLength + endOfLineLength

    func updateHeaders(headers: HTTPHeaders) -> HTTPHeaders {
        var headers = headers
        headers.add(name: "Content-Encoding", value: "aws-chunked")
        return headers
    }
    
    func fillWorkingBuffer(on eventLoop: EventLoop) -> EventLoopFuture<ByteBuffer> {
        workingBuffer.clear()
        // if there is still data available from the previously read buffer then use that
        if var readBuffer = self.previouslyReadBuffer, readBuffer.readableBytes > 0 {
            let bytesToRead = min(Self.bufferSize, readBuffer.readableBytes)
            var slice = readBuffer.readSlice(length: bytesToRead)!
            if readBuffer.readableBytes == 0 {
                self.previouslyReadBuffer = nil
            } else {
                self.previouslyReadBuffer = readBuffer
            }
            workingBuffer.writeBuffer(&slice)
            // if working buffer is full return the buffer
            if workingBuffer.readableBytes == Self.bufferSize {
                return eventLoop.makeSucceededFuture(workingBuffer)
            }
        }
        let promise: EventLoopPromise<ByteBuffer> = eventLoop.makePromise()
        func _fillBuffer() {
            _ = read(eventLoop).map { (buffer) -> Void in
                if buffer.readableBytes == 0 {
                    promise.succeed(self.workingBuffer)
                    return
                }
                // if working buffer is empty and this buffer is the chunk buffer size then just return this buffer
                if self.workingBuffer.readableBytes == 0 && buffer.readableBytes == Self.bufferSize {
                    promise.succeed(buffer)
                    return
                }
                var buffer = buffer
                let bytesRequired = Self.bufferSize - self.workingBuffer.readableBytes
                let bytesToRead = min(buffer.readableBytes, bytesRequired)
                var slice = buffer.readSlice(length: bytesToRead)!
                self.workingBuffer.writeBuffer(&slice)
                if buffer.readableBytes > 0 {
                    self.previouslyReadBuffer = buffer
                }
                if self.workingBuffer.readableBytes == Self.bufferSize {
                    promise.succeed(self.workingBuffer)
                    return
                }
                _fillBuffer()
            }.cascadeFailure(to: promise)
        }
        
        _fillBuffer()
        
        return promise.futureResult
    }
    
    func streamChunks(on eventLoop: EventLoop) -> EventLoopFuture<[ByteBuffer]> {
        return fillWorkingBuffer(on: eventLoop).map { buffer in
            // sign header etc
            self.signingData = self.signer.signChunk(body: .byteBuffer(buffer), signingData: self.signingData)
            let header = "\(String(buffer.readableBytes, radix:16));chunk-signature=\(self.signingData.signature)\r\n"
            self.headerBuffer.clear()
            self.headerBuffer.writeString(header)
            
            return [self.headerBuffer, buffer, self.tailBuffer]
        }
    }
    
    func endChunk() -> ByteBuffer? {
        self.signingData = self.signer.signChunk(body: .byteBuffer(ByteBufferAllocator().buffer(capacity: 0)), signingData: self.signingData)
        let header = "0;chunk-signature=\(self.signingData.signature)\r\n"
        self.headerBuffer.clear()
        self.headerBuffer.writeString(header)
        return self.headerBuffer
    }

    init(size: Int, seedSigningData: AWSSigner.ChunkedSigningData, signer: AWSSigner, byteBufferAllocator: ByteBufferAllocator = ByteBufferAllocator(), read: @escaping (EventLoop)->EventLoopFuture<ByteBuffer>) {
        self.size = size
        self.read = read
        self.signer = signer
        self.signingData = seedSigningData
        // have separate buffers so we aren't allocating 128k
        self.headerBuffer = byteBufferAllocator.buffer(capacity: Self.maxHeaderSize)
        self.workingBuffer = byteBufferAllocator.buffer(capacity: Self.bufferSize)
        self.tailBuffer = byteBufferAllocator.buffer(capacity: Self.endOfLineLength)
        tailBuffer.writeString("\r\n")
        self.previouslyReadBuffer = nil
    }
    
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
        let fullSize = numberOfChunks * (Self.bufferSize + Self.maxHeaderSize + Self.endOfLineLength) + lastChunkSize + Self.maxHeaderSize - 2  // number of chunks * chunk size + end chunk size + tail chunk size
        return fullSize
    }
    let size: Int?
    let read: (EventLoop)->EventLoopFuture<ByteBuffer>

    var signer: AWSSigner
    var signingData: AWSSigner.ChunkedSigningData
    var previouslyReadBuffer: ByteBuffer?
    var headerBuffer: ByteBuffer
    var workingBuffer: ByteBuffer
    var tailBuffer: ByteBuffer
}
