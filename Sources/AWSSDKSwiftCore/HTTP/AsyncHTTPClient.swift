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
    public func execute(request: AWSHTTPRequest, timeout: TimeAmount, on eventLoop: EventLoop?) -> EventLoopFuture<AWSHTTPResponse> {
        if let eventLoop = eventLoop {
            precondition(self.eventLoopGroup.makeIterator().contains { $0 === eventLoop }, "EventLoop provided to AWSClient must be part of the HTTPClient's EventLoopGroup.")
        }
        let requestBody: AsyncHTTPClient.HTTPClient.Body?
        if let body = request.body {
            requestBody = .byteBuffer(body)
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
