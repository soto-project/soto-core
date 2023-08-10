//===----------------------------------------------------------------------===//
//
// This source file is part of the Soto for AWS open source project
//
// Copyright (c) 2023 the Soto project authors
// Licensed under Apache License v2.0
//
// See LICENSE.txt for license information
// See CONTRIBUTORS.txt for the list of Soto project authors
//
// SPDX-License-Identifier: Apache-2.0
//
//===----------------------------------------------------------------------===//

import Tracing

/// Middleware for adding tracing to AWS calls.
///
/// This currently only adds attributes for the basic common attributes as detailed
/// in https://github.com/open-telemetry/semantic-conventions/blob/main/docs/cloud-providers/aws-sdk.md
public struct AWSTracingMiddleware: AWSMiddlewareProtocol {
    public init() {}

    public func handle(
        _ request: AWSHTTPRequest,
        context: AWSMiddlewareContext,
        next: AWSMiddlewareNextHandler
    ) async throws -> AWSHTTPResponse {
        try await InstrumentationSystem.tracer.withSpan(
            "\(context.serviceConfig.serviceName).\(context.operation)",
            ofKind: .client
        ) { span in
            span.updateAttributes { attributes in
                attributes["rpc.system"] = "aws-sdk"
                attributes["rpc.method"] = context.operation
                attributes["rpc.service"] = context.serviceConfig.serviceName
            }
            let response = try await next(request, context)

            span.attributes["aws.request_id"] = response.headers["x-amz-request-id"].first ?? response.headers["x-amz-requestid"].first

            return response
        }
    }
}

extension Span {
    /// Update Span attributes in a block instead of individually
    ///
    /// Updating a span attribute will involve some type of thread synchronisation
    /// primitive to avoid multiple threads updating the attributes at the same
    /// time. If you update each attributes individually this could cause slowdown.
    /// This function updates the attributes in one call to avoid hitting the
    /// thread synchronisation code multiple times
    ///
    /// - Parameter update: closure used to update span attributes
    func updateAttributes(_ update: (inout SpanAttributes) -> Void) {
        var attributes = self.attributes
        update(&attributes)
        self.attributes = attributes
    }
}
