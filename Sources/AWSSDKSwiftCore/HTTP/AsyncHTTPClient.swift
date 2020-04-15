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
        size: Int,
        on eventLoop: EventLoop,
        closure: @escaping (EventLoop)->EventLoopFuture<ByteBuffer>) -> EventLoopFuture<Void> {
        let promise = eventLoop.makePromise(of: Void.self)

        func _writeToStreamWriter(_ amountLeft: Int) {
            // get byte buffer from closure, write to StreamWriter, if there are still bytes to write then call
            // _writeToStreamWriter again.
            _ = closure(eventLoop)
                .map { byteBuffer in
                    let newAmountLeft = amountLeft - byteBuffer.readableBytes
                    _ = writer.write(.byteBuffer(byteBuffer)).flatMap { ()->EventLoopFuture<Void> in
                        if newAmountLeft == 0 {
                            promise.succeed(())
                        } else if newAmountLeft < 0 {
                            promise.fail(AWSClient.RequestError.tooMuchData)
                        } else {
                            _writeToStreamWriter(newAmountLeft)
                        }
                        return promise.futureResult
                    }.cascadeFailure(to: promise)
            }.cascadeFailure(to: promise)
        }
        _writeToStreamWriter(size)
        return promise.futureResult
    }

    func execute(request: AWSHTTPRequest, timeout: TimeAmount, on eventLoop: EventLoop?) -> EventLoopFuture<AWSHTTPResponse> {
        if let eventLoop = eventLoop {
            precondition(self.eventLoopGroup.makeIterator().contains { $0 === eventLoop }, "EventLoop provided to AWSClient must be part of the HTTPClient's EventLoopGroup.")
        }        
        let requestBody: AsyncHTTPClient.HTTPClient.Body?
        if let body = request.body {
            switch body {
            case .byteBuffer(let byteBuffer):
                requestBody = .byteBuffer(byteBuffer)

            case .stream(let size, let closure):
                let eventLoop = eventLoopGroup.next()
                requestBody = .stream(length: size) { writer in
                    return self.writeToStreamWriter(writer: writer, size: size, on: eventLoop, closure: closure)
                }
            }
        } else {
            requestBody = nil
        }
        do {
            let eventLoop = eventLoop ?? eventLoopGroup.next()
            let asyncRequest = try AsyncHTTPClient.HTTPClient.Request(url: request.url, method: request.method, headers: request.headers, body: requestBody)
            return execute(request: asyncRequest, eventLoop: .delegate(on: eventLoop), deadline: .now() + timeout).map { $0 }
        } catch {
            return eventLoopGroup.next().makeFailedFuture(error)
        }
    }
}

extension AsyncHTTPClient.HTTPClient.Response: AWSHTTPResponse {}
