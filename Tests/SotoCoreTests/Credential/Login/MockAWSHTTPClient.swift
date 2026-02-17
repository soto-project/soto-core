//===----------------------------------------------------------------------===//
//
// This source file is part of the Soto for AWS open source project
//
// Copyright (c) 2017-2026 the Soto project authors
// Licensed under Apache License v2.0
//
// See LICENSE.txt for license information
// See CONTRIBUTORS.txt for the list of Soto project authors
//
// SPDX-License-Identifier: Apache-2.0
//
//===----------------------------------------------------------------------===//

// Mock AWS HTTP Client for testing

import Logging
import NIOCore
import NIOHTTP1
import SotoCore

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif

final class MockAWSHTTPClient: AWSHTTPClient {
    private let requestHandler: @Sendable (AWSHTTPRequest) async throws -> (HTTPResponseStatus, Data)

    public init(requestHandler: @escaping (@Sendable (AWSHTTPRequest) async throws -> (HTTPResponseStatus, Data)) = { _ in (.ok, Data()) }) {
        self.requestHandler = requestHandler
    }
    func execute(
        request: AWSHTTPRequest,
        timeout: TimeAmount,
        logger: Logger
    ) async throws -> AWSHTTPResponse {

        let (status, data) = try await requestHandler(request)

        return AWSHTTPResponse(
            status: status,
            headers: HTTPHeaders(),
            body: AWSHTTPBody(bytes: data)
        )
    }

}
