public typealias AWSMiddlewareHandler = @Sendable (AWSHTTPRequest, AWSMiddlewareContext, _ next: (AWSHTTPRequest, AWSMiddlewareContext) async throws -> AWSHTTPResponse) async throws -> AWSHTTPResponse

public protocol AWSMiddlewareProtocol: Sendable {
    func handle(_ input: AWSHTTPRequest, context: AWSMiddlewareContext, next: (AWSHTTPRequest, AWSMiddlewareContext) async throws -> AWSHTTPResponse) async throws -> AWSHTTPResponse
}

public struct AWSMiddleware: AWSMiddlewareProtocol {
    var middleware: AWSMiddlewareHandler

    public init(_ middleware: @escaping AWSMiddlewareHandler) {
        self.middleware = middleware
    }

    public func handle(_ input: AWSHTTPRequest, context: AWSMiddlewareContext, next: (AWSHTTPRequest, AWSMiddlewareContext) async throws -> AWSHTTPResponse) async throws -> AWSHTTPResponse {
        try await self.middleware(input, context, next)
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
    public func handle(_ input: AWSHTTPRequest, context: AWSMiddlewareContext, next: (AWSHTTPRequest, AWSMiddlewareContext) async throws -> AWSHTTPResponse) async throws -> AWSHTTPResponse {
        try await self.m0.handle(input, context: context) { input, context in
            try await self.m1.handle(input, context: context, next: next)
        }
    }
}

public struct AWSDynamicMiddlewareStack: AWSMiddlewareProtocol {
    typealias Stack = [(String, any AWSMiddlewareProtocol)]

    var stack: [(String, any AWSMiddlewareProtocol)]

    public init(_ list: any AWSMiddlewareProtocol...) {
        self.stack = list.enumerated().map { i, m in ("\(i)", m) }
    }

    public func handle(_ input: AWSHTTPRequest, context: AWSMiddlewareContext, next: (AWSHTTPRequest, AWSMiddlewareContext) async throws -> AWSHTTPResponse) async throws -> AWSHTTPResponse {
        let iterator = self.stack.makeIterator()
        return try await self.run(input, context: context, iterator: iterator, finally: next)
    }

    func run(
        _ input: AWSHTTPRequest,
        context: AWSMiddlewareContext,
        iterator: Stack.Iterator,
        finally: (AWSHTTPRequest, AWSMiddlewareContext) async throws -> AWSHTTPResponse
    ) async throws -> AWSHTTPResponse {
        var iterator = iterator
        switch iterator.next() {
        case .none:
            return try await finally(input, context)
        case .some(let middleware):
            return try await middleware.1.handle(input, context: context) { input, context in
                try await self.run(input, context: context, iterator: iterator, finally: finally)
            }
        }
    }
}
