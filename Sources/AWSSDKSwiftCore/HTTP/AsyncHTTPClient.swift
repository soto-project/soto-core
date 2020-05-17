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
import Foundation
import NIO

extension AsyncHTTPClient.HTTPClient.Body.StreamWriter {
    /// Write data out in chunked format "{chunk byte size in hexadecimal}\r\n{chunk}\r\n"
    ///
    /// - Parameters:
    ///   - data: chunk data
    ///   - byteBufferAllocator: byte buffer allocator used to allocate space for header
    func writeChunk(_ chunk: ByteBuffer, byteBufferAllocator: ByteBufferAllocator) -> EventLoopFuture<Void> {
        // chunk header is chunk size in hexadecimal plus carriage return,newline
        let chunkHeader = "\(String(chunk.readableBytes, radix:16, uppercase: true))\r\n"
        let chunkHeaderLength = chunkHeader.utf8.count
        var headerByteBuffer = byteBufferAllocator.buffer(capacity: chunkHeaderLength)
        headerByteBuffer.writeString(chunkHeader)
        // use end of header for tail
        let tailByteBuffer = headerByteBuffer.getSlice(at: headerByteBuffer.readerIndex + chunkHeaderLength - 2, length: 2)!

        _ = write(.byteBuffer(headerByteBuffer))
        _ = write(.byteBuffer(chunk))
        return write(.byteBuffer(tailByteBuffer))
    }
    
    /// Write empty chunk for end of chunked stream
    ///
    /// - Parameter byteBufferAllocator: byte buffer allocator used to allocate space for header
    func writeEmptyChunk(byteBufferAllocator: ByteBufferAllocator) -> EventLoopFuture<Void> {
        let emptyChunk = "0\r\n\r\n"
        var emptyChunkBuffer = byteBufferAllocator.buffer(capacity: emptyChunk.utf8.count)
        emptyChunkBuffer.writeString(emptyChunk)

        return write(.byteBuffer(emptyChunkBuffer))
    }
}

/// comply with AWSHTTPClient protocol
extension AsyncHTTPClient.HTTPClient: AWSHTTPClient {

    /// write stream to StreamWriter
    private func writeToStreamWriter(
        writer: HTTPClient.Body.StreamWriter,
        size: Int?,
        on eventLoop: EventLoop,
        byteBufferAllocator: ByteBufferAllocator,
        getData: @escaping (EventLoop)->EventLoopFuture<ByteBuffer>) -> EventLoopFuture<Void> {
        let promise = eventLoop.makePromise(of: Void.self)

        func _writeToStreamWriter(_ amountLeft: Int?) {
            // get byte buffer from closure, write to StreamWriter, if there are still bytes to write then call
            // _writeToStreamWriter again.
            _ = getData(eventLoop)
                .map { (byteBuffer)->() in
                    // if no amount was set and the byte buffer has no readable bytes then this is assumed to mean
                    // there will be no more data
                    if amountLeft == nil && byteBuffer.readableBytes == 0 {
                        _ = writer.writeEmptyChunk(byteBufferAllocator: byteBufferAllocator).map { _ in
                            promise.succeed(())
                        }.cascadeFailure(to: promise)
                        return
                    }
                    // calculate amount left to write
                    let newAmountLeft = amountLeft.map { $0 - byteBuffer.readableBytes }
                    // write chunk. If amountLeft is nil assume we are writing chunked output
                    let writeFuture: EventLoopFuture<Void>
                    if amountLeft == nil {
                        writeFuture = writer.writeChunk(byteBuffer, byteBufferAllocator: byteBufferAllocator)
                    } else {
                        writeFuture = writer.write(.byteBuffer(byteBuffer))
                    }
                    _ = writeFuture.flatMap { ()->EventLoopFuture<Void> in
                        if let newAmountLeft = newAmountLeft {
                            if newAmountLeft == 0 {
                                promise.succeed(())
                            } else if newAmountLeft < 0 {
                                promise.fail(AWSClient.ClientError.tooMuchData)
                            } else {
                                _writeToStreamWriter(newAmountLeft)
                            }
                        } else {
                            _writeToStreamWriter(nil)
                        }
                        return promise.futureResult
                    }.cascadeFailure(to: promise)
            }.cascadeFailure(to: promise)
        }
        _writeToStreamWriter(size)
        return promise.futureResult
    }
    
    /// Execute HTTP request
    /// - Parameters:
    ///   - request: HTTP request
    ///   - timeout: If execution is idle for longer than timeout then throw error
    ///   - eventLoop: eventLoop to run request on
    /// - Returns: EventLoopFuture that will be fulfilled with request response
    public func execute(request: AWSHTTPRequest, timeout: TimeAmount, on eventLoop: EventLoop?) -> EventLoopFuture<AWSHTTPResponse> {
        if let eventLoop = eventLoop {
            precondition(self.eventLoopGroup.makeIterator().contains { $0 === eventLoop }, "EventLoop provided to AWSClient must be part of the HTTPClient's EventLoopGroup.")
        }        
        let eventLoop = eventLoop ?? eventLoopGroup.next()
        let requestBody: AsyncHTTPClient.HTTPClient.Body?
        var requestHeaders = request.headers
        
        switch request.body.payload {
        case .byteBuffer(let byteBuffer):
            requestBody = .byteBuffer(byteBuffer)
        case .stream(let size, let byteBufferAllocator, let getData):
            // add "Transfer-Encoding" header if streaming with unknown size
            if size == nil {
                requestHeaders.add(name: "Transfer-Encoding", value: "chunked")
            }
            requestBody = .stream(length: size) { writer in
                return self.writeToStreamWriter(writer: writer, size: size, on: eventLoop, byteBufferAllocator: byteBufferAllocator, getData: getData)
            }
        case .empty:
            requestBody = nil
        }
        do {
            let asyncRequest = try AsyncHTTPClient.HTTPClient.Request(url: request.url, method: request.method, headers: requestHeaders, body: requestBody)
            return execute(request: asyncRequest, eventLoop: .delegate(on: eventLoop), deadline: .now() + timeout).map { $0 }
        } catch {
            return eventLoopGroup.next().makeFailedFuture(error)
        }
    }
}

extension AsyncHTTPClient.HTTPClient.Response: AWSHTTPResponse {}
