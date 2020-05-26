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
    
    /// Content size is the same as the size as we aren't adding any chunk headers here
    var contentSize: Int? { return size }
    
    /// size of data to be streamed
    let size: Int?
    /// function providing data to be streamed
    let read: (EventLoop)->EventLoopFuture<ByteBuffer>
    /// bytebuffer allocator
    var byteBufferAllocator: ByteBufferAllocator
}

