//===----------------------------------------------------------------------===//
//
// This source file is part of the Soto for AWS open source project
//
// Copyright (c) 2017-2022 the Soto project authors
// Licensed under Apache License v2.0
//
// See LICENSE.txt for license information
// See CONTRIBUTORS.txt for the list of Soto project authors
//
// SPDX-License-Identifier: Apache-2.0
//
//===----------------------------------------------------------------------===//

#if !os(Linux)
import AsyncHTTPClient
import Foundation
import Logging
import NIOFoundationCompat
import NIOHTTP1

extension URLSession: AWSHTTPClient {
    /// Execute HTTP request
    /// - Parameters:
    ///   - request: HTTP request
    ///   - timeout: If execution is idle for longer than timeout then throw error
    ///   - eventLoop: eventLoop to run request on
    /// - Returns: EventLoopFuture that will be fulfilled with request response
    public func execute(
        request: AWSHTTPRequest,
        timeout: TimeAmount,
        logger: Logger
    ) async throws -> AWSHTTPResponse {
        var urlRequest = URLRequest(url: request.url)
        urlRequest.httpMethod = request.method.rawValue
        for header in request.headers {
            urlRequest.addValue(header.value, forHTTPHeaderField: header.name)
        }
        switch request.body.storage {
        case .byteBuffer(let byteBuffer):
            urlRequest.httpBody = Data(buffer: byteBuffer)
        case .asyncSequence:
            preconditionFailure("Input streams are currently not supported")
        }
        let (data, urlResponse) = try await self.data(for: urlRequest)
        guard let httpURLResponse = urlResponse as? HTTPURLResponse else { preconditionFailure() }
        let statusCode = HTTPResponseStatus(statusCode: httpURLResponse.statusCode)
        var headers = HTTPHeaders()
        for header in httpURLResponse.allHeaderFields {
            guard let name = header.key as? String, let value = header.value as? String else { continue }
            headers.add(name: name, value: value)
        }
        let (bodyStream, bodyStreamContinuation) = AsyncStream<ByteBuffer>.makeStream()
        let body = AWSHTTPBody(asyncSequence: bodyStream, length: data.count)
        bodyStreamContinuation.yield(.init(data: data))
        bodyStreamContinuation.finish()

        return .init(status: statusCode, headers: headers, body: body)
    }
}

#endif // !os(Linux)
