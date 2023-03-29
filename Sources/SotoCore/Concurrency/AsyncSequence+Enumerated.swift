//===----------------------------------------------------------------------===//
//
// This source file is part of the Soto for AWS open source project
//
// Copyright (c) 2017-2023 the Soto project authors
// Licensed under Apache License v2.0
//
// See LICENSE.txt for license information
// See CONTRIBUTORS.txt for the list of Soto project authors
//
// SPDX-License-Identifier: Apache-2.0
//
//===----------------------------------------------------------------------===//

#if compiler(>=5.5.2) && canImport(_Concurrency)

@available(macOS 10.15, iOS 13.0, tvOS 13.0, watchOS 6.0, *)
public struct AsyncEnumeratedSequence<Base: AsyncSequence> {
    @usableFromInline
    let base: Base

    @usableFromInline
    init(_ base: Base) {
        self.base = base
    }
}

@available(macOS 10.15, iOS 13.0, tvOS 13.0, watchOS 6.0, *)
extension AsyncEnumeratedSequence: AsyncSequence {
    public typealias Element = (Int, Base.Element)

    public struct AsyncIterator: AsyncIteratorProtocol {
        @usableFromInline
        var baseIterator: Base.AsyncIterator
        public var index: Int

        public init(baseIterator: Base.AsyncIterator) {
            self.baseIterator = baseIterator
            self.index = 0
        }

        @inlinable
        public mutating func next() async rethrows -> AsyncEnumeratedSequence.Element? {
            let value = try await self.baseIterator.next().map { (self.index, $0) }
            self.index += 1
            return value
        }
    }

    public __consuming func makeAsyncIterator() -> AsyncIterator {
        return .init(baseIterator: self.base.makeAsyncIterator())
    }
}

@available(macOS 10.15, iOS 13.0, tvOS 13.0, watchOS 6.0, *)
extension AsyncEnumeratedSequence: Sendable where Base: Sendable {}

@available(macOS 10.15, iOS 13.0, tvOS 13.0, watchOS 6.0, *)
extension AsyncSequence {
    public func enumerated() -> AsyncEnumeratedSequence<Self> { return AsyncEnumeratedSequence(self) }
}
#endif // compiler(>=5.5.2) && canImport(_Concurrency)
