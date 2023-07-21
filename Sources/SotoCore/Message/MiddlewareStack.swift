
@resultBuilder
public enum MiddlewareBuilder {
    public static func buildBlock<M0: AWSMiddlewareProtocol>(_ m0: M0) -> M0 {
        return m0
    }

    public static func buildPartialBlock<M0: AWSMiddlewareProtocol>(first: M0) -> M0 {
        first
    }

    public static func buildPartialBlock<M0: AWSMiddlewareProtocol, M1: AWSMiddlewareProtocol>(
        accumulated m0: M0,
        next m1: M1
    ) -> Middleware2<M0, M1> {
        Middleware2(m0, m1)
    }
}

public func MiddlewareStack(@MiddlewareBuilder _ builder: () -> some AWSMiddlewareProtocol) -> some AWSMiddlewareProtocol {
    builder()
}
