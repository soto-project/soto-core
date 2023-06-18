//===----------------------------------------------------------------------===//
//
// This source file is part of the Soto for AWS open source project
//
// Copyright (c) 2020-2022 the Soto project authors
// Licensed under Apache License v2.0
//
// See LICENSE.txt for license information
// See CONTRIBUTORS.txt for the list of Soto project authors
//
// SPDX-License-Identifier: Apache-2.0
//
//===----------------------------------------------------------------------===//

import struct Foundation.URL
import NIOCore

/// Services object protocol. Contains a client to communicate with AWS and configuration for defining how to communicate.
public protocol AWSService: Sendable {
    /// Client used to communicate with AWS
    var client: AWSClient { get }
    /// Service context details
    var config: AWSServiceConfig { get }
    /// Create new version of service with patch
    ///
    /// This is required to support ``with(region:middlewares:timeout:byteBufferAllocator:options:)``.
    /// Standard implementation is as follows
    /// ```swift
    /// public init(from: MyService, patch: AWSServiceConfig.Patch) {
    ///     self.client = from.client
    ///     self.config = from.config.with(patch: patch)
    /// }
    /// ```
    init(from: Self, patch: AWSServiceConfig.Patch)
}

extension AWSService {
    /// Region where service is running
    public var region: Region { return config.region }
    /// The url to use in requests
    public var endpoint: String { return config.endpoint }
    /// The EventLoopGroup service is using
    public var eventLoopGroup: EventLoopGroup { return client.eventLoopGroup }

    /// Return new version of Service with edited parameters
    /// - Parameters:
    ///   - region: Server region
    ///   - middlewares: Additional middleware to add
    ///   - timeout: Time out value for HTTP requests
    ///   - byteBufferAllocator: byte buffer allocator used throughout AWSClient
    ///   - options: options used by client when processing requests
    /// - Returns: New version of the service
    public func with(
        region: Region? = nil,
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
