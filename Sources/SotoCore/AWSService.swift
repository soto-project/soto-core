//===----------------------------------------------------------------------===//
//
// This source file is part of the Soto for AWS open source project
//
// Copyright (c) 2020 the Soto project authors
// Licensed under Apache License v2.0
//
// See LICENSE.txt for license information
// See CONTRIBUTORS.txt for the list of Soto project authors
//
// SPDX-License-Identifier: Apache-2.0
//
//===----------------------------------------------------------------------===//

import Baggage
import struct Foundation.URL
import NIO

/// Protocol for services objects. Contains a client to communicate with AWS and config for defining how to communicate
public protocol AWSService {
    /// Client used to communicate with AWS
    var client: AWSClient { get }
    /// Service context details
    var config: AWSServiceConfig { get }
    /// Patch initialization
    init(from: Self, patch: AWSServiceConfig.Patch)
}

extension AWSService {
    /// Region where service is running
    public var region: Region { return config.region }
    /// The url to use in requests
    public var endpoint: String { return config.endpoint }
    /// The EventLoopGroup service is using
    public var eventLoopGroup: EventLoopGroup { return client.eventLoopGroup }

    /// Generate a signed URL
    /// - parameters:
    ///     - url : URL to sign
    ///     - httpMethod: HTTP method to use (.GET, .PUT, .PUSH etc)
    ///     - headers: Headers that are to be used with this URL. Be sure to include these headers when you used the returned URL
    ///     - expires: How long before the signed URL expires
    ///     - logger: Logger to output to
    /// - returns:
    ///     A signed URL
    public func signURL(
        url: URL,
        httpMethod: HTTPMethod,
        headers: HTTPHeaders = HTTPHeaders(),
        expires: TimeAmount,
        context: LoggingContext
    ) -> EventLoopFuture<URL> {
        return self.client.signURL(url: url, httpMethod: httpMethod, headers: headers, expires: expires, serviceConfig: self.config, context: context)
    }

    /// Generate signed headers
    /// - parameters:
    ///     - url : URL to sign
    ///     - httpMethod: HTTP method to use (.GET, .PUT, .PUSH etc)
    ///     - headers: Headers that are to be used with this URL. Be sure to include these headers when you used the returned URL
    ///     - body: body payload to sign as well. While it is unnecessary to provide the body for S3 other services require it
    ///     - logger: Logger to output to
    /// - returns:
    ///     A series of signed headers including the original headers provided to the function
    public func signHeaders(
        url: URL,
        httpMethod: HTTPMethod,
        headers: HTTPHeaders = HTTPHeaders(),
        body: AWSPayload = .empty,
        context: LoggingContext
    ) -> EventLoopFuture<HTTPHeaders> {
        return self.client.signHeaders(url: url, httpMethod: httpMethod, headers: headers, body: body, serviceConfig: self.config, context: context)
    }

    /// Return new version of Service with edited parameters
    /// - Parameters:
    ///   - middlewares: Additional middleware to add
    ///   - timeout: Time out value for HTTP requests
    ///   - byteBufferAllocator: byte buffer allocator used throughout AWSClient
    ///   - options: options used by client when processing requests
    /// - Returns: New version of the service
    public func with(
        middlewares: [AWSServiceMiddleware] = [],
        timeout: TimeAmount? = nil,
        byteBufferAllocator: ByteBufferAllocator? = nil,
        options: AWSServiceConfig.Options? = nil
    ) -> Self {
        return Self(from: self, patch: .init(
            region: region,
            middlewares: middlewares,
            timeout: timeout,
            byteBufferAllocator: byteBufferAllocator,
            options: options
        ))
    }

    /// Return new version of Service with edited parameters
    /// - Parameters:
    ///   - region: Server region
    ///   - middlewares: Additional middleware to add
    ///   - timeout: Time out value for HTTP requests
    ///   - byteBufferAllocator: byte buffer allocator used throughout AWSClient
    ///   - options: options used by client when processing requests
    /// - Returns: New version of the service
    public func with(
        region: Region,
        middlewares: [AWSServiceMiddleware] = [],
        timeout: TimeAmount? = nil,
        byteBufferAllocator: ByteBufferAllocator? = nil,
        options: AWSServiceConfig.Options? = nil
    ) -> Self {
        return Self(from: self, patch: .init(
            region: region,
            middlewares: middlewares,
            timeout: timeout,
            byteBufferAllocator: byteBufferAllocator,
            options: options
        ))
    }
}
