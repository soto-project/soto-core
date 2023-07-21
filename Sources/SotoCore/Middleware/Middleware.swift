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

import Logging

/// Context object sent to `AWSMiddlewareProtocol` `handle` functions
public struct AWSMiddlewareContext {
    public let operation: String
    public let serviceConfig: AWSServiceConfig
    public let logger: Logger
}

public typealias AWSMiddlewareHandler = @Sendable (AWSHTTPRequest, AWSMiddlewareContext, _ next: (AWSHTTPRequest, AWSMiddlewareContext) async throws -> AWSHTTPResponse) async throws -> AWSHTTPResponse

public protocol AWSMiddlewareProtocol: Sendable {
    func handle(_ request: AWSHTTPRequest, context: AWSMiddlewareContext, next: (AWSHTTPRequest, AWSMiddlewareContext) async throws -> AWSHTTPResponse) async throws -> AWSHTTPResponse
}

public struct AWSMiddleware: AWSMiddlewareProtocol {
    var middleware: AWSMiddlewareHandler

    public init(_ middleware: @escaping AWSMiddlewareHandler) {
        self.middleware = middleware
    }

    public func handle(_ request: AWSHTTPRequest, context: AWSMiddlewareContext, next: (AWSHTTPRequest, AWSMiddlewareContext) async throws -> AWSHTTPResponse) async throws -> AWSHTTPResponse {
        try await self.middleware(request, context, next)
    }
}

public struct Middleware2<M0: AWSMiddlewareProtocol, M1: AWSMiddlewareProtocol>: AWSMiddlewareProtocol {
    @usableFromInline let m0: M0
    @usableFromInline let m1: M1

    @inlinable
    public init(_ m0: M0, _ m1: M1) {
        self.m0 = m0
        self.m1 = m1
    }

    @inlinable
    public func handle(_ request: AWSHTTPRequest, context: AWSMiddlewareContext, next: (AWSHTTPRequest, AWSMiddlewareContext) async throws -> AWSHTTPResponse) async throws -> AWSHTTPResponse {
        try await self.m0.handle(request, context: context) { request, context in
            try await self.m1.handle(request, context: context, next: next)
        }
    }
}

public struct AWSDynamicMiddlewareStack: AWSMiddlewareProtocol {
    typealias Stack = [(String, any AWSMiddlewareProtocol)]

    var stack: [(String, any AWSMiddlewareProtocol)]

    public init(_ list: any AWSMiddlewareProtocol...) {
        self.init(list)
    }

    public init(_ list: [any AWSMiddlewareProtocol]) {
        self.stack = list.enumerated().map { i, m in ("\(i)", m) }
    }

    public func handle(_ request: AWSHTTPRequest, context: AWSMiddlewareContext, next: (AWSHTTPRequest, AWSMiddlewareContext) async throws -> AWSHTTPResponse) async throws -> AWSHTTPResponse {
        let iterator = self.stack.makeIterator()
        return try await self.run(request, context: context, iterator: iterator, finally: next)
    }

    func run(
        _ request: AWSHTTPRequest,
        context: AWSMiddlewareContext,
        iterator: Stack.Iterator,
        finally: (AWSHTTPRequest, AWSMiddlewareContext) async throws -> AWSHTTPResponse
    ) async throws -> AWSHTTPResponse {
        var iterator = iterator
        switch iterator.next() {
        case .none:
            return try await finally(request, context)
        case .some(let middleware):
            return try await middleware.1.handle(request, context: context) { request, context in
                try await self.run(request, context: context, iterator: iterator, finally: finally)
            }
        }
    }
}

public struct PassThruMiddleware: AWSMiddlewareProtocol {
    public init() {}

    public func handle(_ request: AWSHTTPRequest, context: AWSMiddlewareContext, next: (AWSHTTPRequest, AWSMiddlewareContext) async throws -> AWSHTTPResponse) async throws -> AWSHTTPResponse {
        try await next(request, context)
    }
}
