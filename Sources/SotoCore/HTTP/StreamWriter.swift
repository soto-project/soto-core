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

protocol ParentStreamWriter {
    /// write to stream
    func write(_ result: StreamWriterResult)
}

/// Protocol for objects that supply streamed data to HTTPClient.Body.StreamWriter
protocol StreamWriter: ParentStreamWriter {
    var length: Int? { get }
    /// Update headers for this kind of streamed data
    /// - Parameter headers: headers to update
    func updateHeaders(headers: HTTPHeaders) -> HTTPHeaders

    func setParentWriter(_ writer: ParentStreamWriter)

    var finishedPromise: EventLoopPromise<Void> { get }
}

extension StreamWriter {
    func updateHeaders(headers: HTTPHeaders) -> HTTPHeaders { return headers }
    var length: Int? { nil }
    func setParentWriter(_ writer: StreamWriter) {}
}

extension AsyncHTTPClient.HTTPClient.Body.StreamWriter: ParentStreamWriter {
    func write(_ result: StreamWriterResult) {
        switch result {
        case .byteBuffer(let buffer):
            _ = self.write(IOData.byteBuffer(buffer))
        case .end:
            break
        }
    }
}

public class ChunkedStreamWriter: StreamWriter {
    var length: Int?
    var writerPromise: EventLoopPromise<ParentStreamWriter>
    var finishedPromise: EventLoopPromise<Void>

    init(length: Int? = nil, eventLoop: EventLoop) {
        self.length = length
        self.writerPromise = eventLoop.makePromise()
        self.finishedPromise = eventLoop.makePromise()
    }

    func setParentWriter(_ writer: ParentStreamWriter) {
        writerPromise.succeed(writer)
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

    public func write(_ result: StreamWriterResult) {
        writerPromise.futureResult.whenSuccess { writer in
            switch result {
            case .byteBuffer(let buffer):
                _ = writer.write(.byteBuffer(buffer))
            case .end:
                self.finishedPromise.succeed(())
            }
        }
    }
}
