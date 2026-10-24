//===----------------------------------------------------------------------===//
//
// This source file is part of the Soto for AWS open source project
//
// Copyright (c) 2022-2023 the Soto project authors
// Licensed under Apache License v2.0
//
// See LICENSE.txt for license information
// See CONTRIBUTORS.txt for the list of Soto project authors
//
// SPDX-License-Identifier: Apache-2.0
//
//===----------------------------------------------------------------------===//

public import HTTPTypes

/// Middleware for editing header values sent to AWS service.
public struct AWSEditHeadersMiddleware: AWSMiddlewareProtocol {
    public enum HeaderEdit {
        case add(name: HTTPField.Name, value: String)
        case replace(name: HTTPField.Name, value: String)
        case remove(name: HTTPField.Name)
    }

    @usableFromInline
    let edits: [HeaderEdit]

    public init(_ edits: [HeaderEdit]) {
        self.edits = edits
    }

    public init(_ edits: HeaderEdit...) {
        self.init(edits)
    }

    @inlinable
    public func handle(_ request: AWSHTTPRequest, context: AWSMiddlewareContext, next: AWSMiddlewareNextHandler) async throws -> AWSHTTPResponse {
        var request = request
        for edit in self.edits {
            switch edit {
            case .add(let name, let value):
                request.request.headerFields[values: name].append(value)
            case .replace(let name, let value):
                request.request.headerFields[name] = value
            case .remove(let name):
                request.request.headerFields[name] = nil
            }
        }
        return try await next(request, context)
    }
}

extension AWSEditHeadersMiddleware: Sendable {}
extension AWSEditHeadersMiddleware.HeaderEdit: Sendable {}
