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

import HTTPTypes
import Logging
import NIOCore
import SotoCore

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif

package final class MockAWSHTTPClient: AWSHTTPClient {
    private let requestHandler: @Sendable (AWSHTTPRequest) async throws -> AWSHTTPResponse

    package init(
        requestHandler: @escaping (@Sendable (AWSHTTPRequest) async throws -> AWSHTTPResponse) = { _ in .init(response: .init(status: .ok)) }
    ) {
        self.requestHandler = requestHandler
    }
    package func execute(
        request: AWSHTTPRequest,
        timeout: Duration,
        logger: Logger
    ) async throws -> AWSHTTPResponse {
        try await requestHandler(request)
    }
}
