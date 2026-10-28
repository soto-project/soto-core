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
        let response: AWSHTTPResponse
        do {
            response = try await requestHandler(request)
        } catch {
            response = .init(
                response: .init(status: .internalServerError),
                body: .init(string: "{\"__type\":\"Internal Failure\", \"message\": \"\(error)\"}")
            )
        }
        var responseHead = response.response
        if let length = response.body.length {
            responseHead.headerFields[.contentLength] = String(length)
        } else if responseHead.headerFields[.contentLength] == nil {
            responseHead.headerFields[.transferEncoding] = "chunked"
        }
        return AWSHTTPResponse(response: responseHead, body: response.body)
    }

    package static func awsError(status: HTTPResponse.Status, code: String, message: String? = nil) -> AWSHTTPResponse {
        if let message {
            AWSHTTPResponse(response: .init(status: status), body: .init(string: "{\"__type\":\"\(code)\", \"message\": \"\(message)\"}"))
        } else {
            AWSHTTPResponse(response: .init(status: status), body: .init(string: "{\"__type\":\"\(code)\"}"))
        }
    }
}
