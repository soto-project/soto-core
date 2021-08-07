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

import AsyncHTTPClient
import NIO
import NIOHTTP1

/// Streaming result
public enum StreamWriterResult {
    case byteBuffer(ByteBuffer)
    case end
}

protocol ChildStreamWriter {
    /// write to stream
    @discardableResult func write(_ result: StreamWriterResult, on eventLoop: EventLoop) -> EventLoopFuture<Void>
}

extension AsyncHTTPClient.HTTPClient.Body.StreamWriter: ChildStreamWriter {
    func write(_ result: StreamWriterResult, on eventLoop: EventLoop) -> EventLoopFuture<Void> {
        switch result {
        case .byteBuffer(let buffer):
            return self.write(IOData.byteBuffer(buffer)).hop(to: eventLoop)
        case .end:
            return eventLoop.makeSucceededVoidFuture()
        }
    }
}

/// Protocol for objects that supply streamed data to HTTPClient.Body.StreamWriter
protocol StreamWriter: ChildStreamWriter {
    var length: Int? { get }
    var eventLoop: EventLoop { get }
    var writerPromise: EventLoopPromise<ChildStreamWriter> { get }
    var finishedPromise: EventLoopPromise<Void> { get }
    /// Update headers for this kind of streamed data
    /// - Parameter headers: headers to update
    func updateHeaders(headers: HTTPHeaders) -> HTTPHeaders
    func write(_ result: StreamWriterResult, to: ChildStreamWriter) -> EventLoopFuture<Void>
}

extension StreamWriter {
    @discardableResult public func write(_ result: StreamWriterResult) -> EventLoopFuture<Void> {
        return write(result, on: eventLoop)
    }
    func updateHeaders(headers: HTTPHeaders) -> HTTPHeaders { return headers }
    var length: Int? { nil }
    func setChildWriter(_ writer: ChildStreamWriter) {
        writerPromise.succeed(writer)
    }

    @discardableResult func write(_ result: StreamWriterResult, on eventLoop: EventLoop) -> EventLoopFuture<Void> {
        return writerPromise.futureResult.flatMap { writer in
            write(result, to: writer)
        }
    }
}

public class ChunkedStreamWriter: StreamWriter {
    let length: Int?
    let eventLoop: EventLoop
    let writerPromise: EventLoopPromise<ChildStreamWriter>
    let finishedPromise: EventLoopPromise<Void>

    init(length: Int? = nil, eventLoop: EventLoop) {
        self.length = length
        self.eventLoop = eventLoop
        self.writerPromise = eventLoop.makePromise()
        self.finishedPromise = eventLoop.makePromise()
    }

    /// Update headers. Add "Transfer-encoding" header if we don't have a steam size
    /// - Parameter headers: headers to update
    func updateHeaders(headers: HTTPHeaders) -> HTTPHeaders {
        var headers = headers
        // add "Transfer-Encoding" header if streaming with unknown size
        if self.length == nil {
            headers.add(name: "Transfer-Encoding", value: "chunked")
        }
        return headers
    }

    func write(_ result: StreamWriterResult, to writer: ChildStreamWriter) -> EventLoopFuture<Void> {
        switch result {
        case .byteBuffer(let buffer):
            return writer.write(.byteBuffer(buffer), on: eventLoop).hop(to: eventLoop)
        case .end:
            self.finishedPromise.succeed(())
            return eventLoop.makeSucceededVoidFuture()
        }
    }
}
