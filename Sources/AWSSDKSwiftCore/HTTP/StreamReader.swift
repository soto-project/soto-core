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

/// Protocol for objects that supply streamed data to HTTPClient.Body.StreamWriter
protocol StreamReader {
    
    /// size of data to be streamed
    var size: Int? { get }
    /// total size of data to be streamed plus any chunk headers
    var contentSize: Int? { get }
    /// function providing data to be streamed
    var read: (EventLoop)->EventLoopFuture<ByteBuffer> { get }
    /// bytebuffer allocator
    var byteBufferAllocator: ByteBufferAllocator { get }
    
    /// Update headers for this kind of streamed data
    /// - Parameter headers: headers to update
    func updateHeaders(headers: HTTPHeaders) -> HTTPHeaders
    
    /// Provide a list of ByteBuffers to write. Back pressure is applied on the last buffer
    /// - Parameter eventLoop: eventLoop to use when generating the event loop future
    func streamChunks(on eventLoop: EventLoop) -> EventLoopFuture<[ByteBuffer]>
    
    /// Return an end of stream marker
    func endChunk() -> ByteBuffer?
    
    /// size of end chunk
    var endChunkSize: Int { get }
    
}

/// Standard chunked streamer. Adds transfer-encoding : chunked header if a size is not supplied. NIO adds all the chunk headers
/// so it just passes the streamed data straight through to the StreamWriter
struct ChunkedStreamReader: StreamReader {

    /// Update headers. Add "Transfer-encoding" header if we don't have a steam size
    /// - Parameter headers: headers to update
    func updateHeaders(headers: HTTPHeaders) -> HTTPHeaders {
        var headers = headers
        // add "Transfer-Encoding" header if streaming with unknown size
        if size == nil {
            headers.add(name: "Transfer-Encoding", value: "chunked")
        }
        return headers
    }
    
    /// Provide a list of ByteBuffers to write. The `ChunkedStreamReader` just passes the `ByteBuffer` supplied to straight through
    /// - Parameter eventLoop: eventLoop to use when generating the event loop future
    func streamChunks(on eventLoop: EventLoop) -> EventLoopFuture<[ByteBuffer]> {
        return read(eventLoop).map { (byteBuffer) -> [ByteBuffer] in
            if byteBuffer.readableBytes > 0 {
                return [byteBuffer]
            } else {
                return []
            }
        }
    }
    
    /// Return an end of stream marker. No end of stream marker is required here
    /// - Returns: nil
    func endChunk() -> ByteBuffer? {
        return nil
    }
    
    /// Size of end chunk
    let endChunkSize: Int = 0

    /// Content size is the same as the size as we aren't adding any chunk headers here
    var contentSize: Int? { return size }
    
    /// size of data to be streamed
    let size: Int?
    /// function providing data to be streamed
    let read: (EventLoop)->EventLoopFuture<ByteBuffer>
    /// bytebuffer allocator
    var byteBufferAllocator: ByteBufferAllocator
}

/// AWS Chunked streamer
class AWSChunkedStreamReader: StreamReader {
    /// Working buffer size
    static let bufferSize: Int = 64*1024
    static let bufferSizeInHex: String = String(bufferSize, radix: 16)
    static let bufferSizeLength = bufferSizeInHex.count
    static let chunkSignatureLength = 1 + 16 + 64 // ";" + "chunk-signature=" + hex(sha256)
    static let endOfLineLength = 2
    /// Maximum size of chunk header
    static let maxHeaderSize: Int = bufferSizeInHex.count + chunkSignatureLength + endOfLineLength
    
    /// Initialise a AWSChunkedStreamReader
    init(size: Int, seedSigningData: AWSSigner.ChunkedSigningData, signer: AWSSigner, byteBufferAllocator: ByteBufferAllocator = ByteBufferAllocator(), read: @escaping (EventLoop)->EventLoopFuture<ByteBuffer>) {
        self.size = size
        self.read = read
        self.signer = signer
        self.signingData = seedSigningData
        // have separate buffers so we aren't allocating 128k
        self.byteBufferAllocator = byteBufferAllocator
        self.headerBuffer = byteBufferAllocator.buffer(capacity: Self.maxHeaderSize)
        self.workingBuffer = byteBufferAllocator.buffer(capacity: Self.bufferSize)
        self.tailBuffer = byteBufferAllocator.buffer(capacity: Self.endOfLineLength)
        tailBuffer.writeString("\r\n")
        self.previouslyReadBuffer = nil
    }
    
    /// Update HTTP headers. Add "Content-encoding" header
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
                // This allows us to avoid the buffer copy
                if self.workingBuffer.readableBytes == 0 && buffer.readableBytes == Self.bufferSize {
                    promise.succeed(buffer)
                    return
                }
                var buffer = buffer
                let bytesRequired = Self.bufferSize - self.workingBuffer.readableBytes
                let bytesToRead = min(buffer.readableBytes, bytesRequired)
                var slice = buffer.readSlice(length: bytesToRead)!
                self.workingBuffer.writeBuffer(&slice)
                // if working buffer is full then call succeed on the promise
                if self.workingBuffer.readableBytes == Self.bufferSize {
                    // if the supplied buffer still has readable bytes then store this buffer so those bytes can
                    // be used in the next call to `fillWorkingBuffer`.
                    if buffer.readableBytes > 0 {
                        self.previouslyReadBuffer = buffer
                    }
                    promise.succeed(self.workingBuffer)
                    return
                }
                _fillBuffer()
            }.cascadeFailure(to: promise)
        }
        
        _fillBuffer()
        
        return promise.futureResult
    }
    
    /// Provide a list of `ByteBuffers` to `StreamWriter`. This function fills the working buffer and then signs it
    /// and returns it along with `ByteBuffers` that contain the header and tail data.
    /// - Parameter eventLoop: EventLoop to run everythin off
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
    
    /// Return the end chunk
    func endChunk() -> ByteBuffer? {
        self.signingData = self.signer.signChunk(body: .byteBuffer(ByteBufferAllocator().buffer(capacity: 0)), signingData: self.signingData)
        let header = "0;chunk-signature=\(self.signingData.signature)\r\n\r\n"
        self.headerBuffer.clear()
        self.headerBuffer.writeString(header)
        return self.headerBuffer
    }
    
    var endChunkSize: Int { return 1 + Self.chunkSignatureLength + Self.endOfLineLength * 2 }
    
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
        let fullSize = numberOfChunks * (Self.bufferSize + Self.maxHeaderSize + Self.endOfLineLength) + lastChunkSize + 1 + Self.chunkSignatureLength + Self.endOfLineLength * 2  // number of chunks * chunk size + end chunk size + tail chunk size
        return fullSize
    }
    /// size of data to be streamed
    let size: Int?
    /// function providing data to be streamed
    let read: (EventLoop)->EventLoopFuture<ByteBuffer>
    /// bytebuffer allocator
    var byteBufferAllocator: ByteBufferAllocator

    var signer: AWSSigner
    var signingData: AWSSigner.ChunkedSigningData
    var previouslyReadBuffer: ByteBuffer?
    var headerBuffer: ByteBuffer
    var workingBuffer: ByteBuffer
    var tailBuffer: ByteBuffer
}
