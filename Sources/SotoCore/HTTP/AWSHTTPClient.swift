//===----------------------------------------------------------------------===//
//
// This source file is part of the Soto for AWS open source project
//
// Copyright (c) 2024 the Soto project authors
// Licensed under Apache License v2.0
//
// See LICENSE.txt for license information
// See CONTRIBUTORS.txt for the list of Soto project authors
//
// SPDX-License-Identifier: Apache-2.0
//
//===----------------------------------------------------------------------===//

/// Protocol for HTTP clients that work with Soto
public protocol AWSHTTPClient: Sendable {
    /// Execute an HTTP request
    func execute(
        request: AWSHTTPRequest,
        timeout: TimeAmount,
        logger: Logger
    ) async throws -> AWSHTTPResponse
    /// Shutdown client if Soto created it
    func shutdown() async throws
}

extension AWSHTTPClient {
    public func shutdown() async throws {}
}
