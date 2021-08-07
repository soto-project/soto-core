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

/// protocol for chaining stream writers together ending with the AsyncHTTPClient stream writer
protocol ChildStreamWriter {
    /// write to stream
    @discardableResult func write(_ result: StreamWriterResult, on eventLoop: EventLoop) -> EventLoopFuture<Void>
}

/// extend so we can add to end of chain of stream writers
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
protocol StreamWriterProtocol: ChildStreamWriter {
    /// length of data to stream
    var length: Int? { get }
    /// event loop to run stream writer on
    var eventLoop: EventLoop { get }
    /// child writer promise
    var writerPromise: EventLoopPromise<ChildStreamWriter> { get }
    /// finished streaming promise
    var finishedPromise: EventLoopPromise<Void> { get }
    /// Update headers for this kind of streamed data
    /// - Parameter headers: headers to update
    func updateHeaders(headers: HTTPHeaders) -> HTTPHeaders
    /// Write result to child stream writer
    /// - Parameters:
    ///   - result: result to write
    ///   - to: stream writer to write to
    func write(_ result: StreamWriterResult, to: ChildStreamWriter) -> EventLoopFuture<Void>
}

extension StreamWriterProtocol {
    /// Write to stream writer
    /// - Parameter result: ByteBuffer or `.end`
    /// - Returns: Returns when EventLoopFuture for when value has been written
    @discardableResult public func write(_ result: StreamWriterResult) -> EventLoopFuture<Void> {
        return self.write(result, on: eventLoop).cascadeFailure(to: finishedPromise)
    }

    /// Default implementation of updateHeaders returns the same headers back
    func updateHeaders(headers: HTTPHeaders) -> HTTPHeaders { return headers }
    /// Default implementation of `length` returns nil
    var length: Int? { nil }
    /// Set the child writer this steam writer should write to
    func setChildWriter(_ writer: ChildStreamWriter) {
        writerPromise.succeed(writer)
    }

    /// Write value to StreamWriter
    @discardableResult func write(_ result: StreamWriterResult, on eventLoop: EventLoop) -> EventLoopFuture<Void> {
        return writerPromise.futureResult.flatMap { writer in
            write(result, to: writer)
        }
    }
}

/// Public stream writer class.
///
/// Forwards all values written to it to next stream writer in the chain ie it's child stream writer
public class AWSStreamWriter: StreamWriterProtocol {
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
            return writer.write(.byteBuffer(buffer), on: self.eventLoop).hop(to: self.eventLoop)
        case .end:
            self.finishedPromise.succeed(())
            return writer.write(result, on: self.eventLoop).hop(to: self.eventLoop)
        }
    }
}
