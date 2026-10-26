//===----------------------------------------------------------------------===//
//
// This source file is part of the Soto for AWS open source project
//
// Copyright (c) 2020-2026 the Soto project authors
// Licensed under Apache License v2.0
//
// See LICENSE.txt for license information
// See CONTRIBUTORS.txt for the list of Soto project authors
//
// SPDX-License-Identifier: Apache-2.0
//
//===----------------------------------------------------------------------===//

public import HTTPTypes
public import Logging
public import NIOCore

#if canImport(FoundationEssentials)
public import FoundationEssentials
#else
public import Foundation
#endif

/// Services object protocol. Contains a client to communicate with AWS and configuration for defining how to communicate.
public protocol AWSService: Sendable {
    /// Client used to communicate with AWS
    var client: AWSClient { get }
    /// Service context details
    var config: AWSServiceConfig { get }
    /// Create new version of service with patch
    ///
    /// This is required to support ``with(region:middleware:timeout:byteBufferAllocator:options:)``.
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
    public var region: Region { config.region }
    /// The url to use in requests
    public var endpoint: String { config.endpoint }

    /// Return new version of Service with edited parameters
    /// - Parameters:
    ///   - region: Server region
    ///   - middleware: Additional middleware to add
    ///   - timeout: Time out value for HTTP requests
    ///   - byteBufferAllocator: byte buffer allocator used throughout AWSClient
    ///   - options: options used by client when processing requests
    /// - Returns: New version of the service
    public func with(
        region: Region? = nil,
        middleware: (any AWSMiddlewareProtocol)? = nil,
        timeout: Duration? = nil,
        byteBufferAllocator: ByteBufferAllocator? = nil,
        options: AWSServiceConfig.Options? = nil
    ) -> Self {
        Self(
            from: self,
            patch: .init(
                region: region,
                middleware: middleware,
                timeout: timeout,
                byteBufferAllocator: byteBufferAllocator,
                options: options
            )
        )
    }

    /// Generate a signed URL
    /// - parameters:
    ///     - request: HTTPRequest to generate signed URL for
    ///     - expires: How long before the signed URL expires
    ///     - logger: Logger to output to
    /// - returns:
    ///     A signed URL
    public func signURL(
        request: HTTPRequest,
        expires: Duration,
        logger: Logger = AWSClient.loggingDisabled
    ) async throws -> URL {
        try await self.client.signURL(
            request: request,
            expires: expires,
            serviceConfig: self.config,
            logger: logger
        )
    }

    /// Generate signed headers
    /// - parameters:
    ///     - request: HTTPRequest to sign.
    ///     - body: body payload to sign as well. While it is unnecessary to provide the body for S3 other services require it
    ///     - logger: Logger to output to
    public func signHeaders(
        request: inout HTTPRequest,
        body: AWSHTTPBody? = nil,
        logger: Logger = AWSClient.loggingDisabled
    ) async throws {
        try await self.client.signHeaders(request: &request, body: body, serviceConfig: self.config, logger: logger)
    }
}
