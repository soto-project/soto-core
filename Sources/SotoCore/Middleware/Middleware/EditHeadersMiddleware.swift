//===----------------------------------------------------------------------===//
//
// This source file is part of the Soto for AWS open source project
//
// Copyright (c) 2022 the Soto project authors
// Licensed under Apache License v2.0
//
// See LICENSE.txt for license information
// See CONTRIBUTORS.txt for the list of Soto project authors
//
// SPDX-License-Identifier: Apache-2.0
//
//===----------------------------------------------------------------------===//

import NIOHTTP1

/// Middleware for editing header values sent to AWS service.
public struct AWSEditHeadersMiddleware: AWSMiddlewareProtocol {
    public enum HeaderEdit {
        case add(name: String, value: String)
        case replace(name: String, value: String)
        case remove(name: String)
    }

    let edits: [HeaderEdit]

    public init(_ edits: [HeaderEdit]) {
        self.edits = edits
    }

    public init(_ edits: HeaderEdit...) {
        self.init(edits)
    }

    public func handle(_ request: AWSHTTPRequest, context: AWSMiddlewareContext, next: (AWSHTTPRequest, AWSMiddlewareContext) async throws -> AWSHTTPResponse) async throws -> AWSHTTPResponse {
        var request = request
        for edit in self.edits {
            switch edit {
            case .add(let name, let value):
                request.headers.add(name: name, value: value)
            case .replace(let name, let value):
                request.headers.replaceOrAdd(name: name, value: value)
            case .remove(let name):
                request.headers.remove(name: name)
            }
        }
        return try await next(request, context)
    }
}

extension AWSEditHeadersMiddleware: Sendable {}
extension AWSEditHeadersMiddleware.HeaderEdit: Sendable {}
