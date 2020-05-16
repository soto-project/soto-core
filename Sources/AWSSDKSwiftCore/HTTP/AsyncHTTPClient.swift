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

/// comply with AWSHTTPClient protocol
extension AsyncHTTPClient.HTTPClient: AWSHTTPClient {

    /// write stream to StreamWriter
    private func writeToStreamWriter(
        writer: HTTPClient.Body.StreamWriter,
        size: Int?,
        on eventLoop: EventLoop,
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
                        promise.succeed(())
                        return
                    }
                    let newAmountLeft = amountLeft.map { $0 - byteBuffer.readableBytes }
                    _ = writer.write(.byteBuffer(byteBuffer)).flatMap { ()->EventLoopFuture<Void> in
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
        case .stream(let size, let getData):
            // add "Transfer-Encoding" header if streaming with unknown size
            if size == nil {
                requestHeaders.add(name: "Transfer-Encoding", value: "chunked")
            }
            requestBody = .stream(length: size) { writer in
                return self.writeToStreamWriter(writer: writer, size: size, on: eventLoop, getData: getData)
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
