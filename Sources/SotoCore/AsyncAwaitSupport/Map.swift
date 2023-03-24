//===----------------------------------------------------------------------===//
//
// This source file is part of the Soto for AWS open source project
//
// Copyright (c) 2017-2022 the Soto project authors
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
extension Sequence where Element: Sendable {
    /// Returns an array containing the results of mapping the given async closure over
    /// the sequence’s elements.
    ///
    /// The closure calls are made serially. The next call is only made once the previous call
    /// has finished. Returns once the closure has run on all the elements of the Sequence
    /// or when the closure throws an error.
    /// - Parameter transform: An async  mapping closure. transform accepts an
    ///     element of this sequence as its parameter and returns a transformed value of
    ///     the same or of a different type.
    /// - Returns: An array containing the transformed elements of this sequence.
    public func asyncMap<T: Sendable>(_ transform: @Sendable @escaping (Element) async throws -> T) async rethrows -> [T] {
        let initialCapacity = underestimatedCount
        var result = ContiguousArray<T>()
        result.reserveCapacity(initialCapacity)

        for element in self {
            try await result.append(transform(element))
        }
        return Array(result)
    }

    /// Returns an array containing the results of mapping the given async closure over
    /// the sequence’s elements.
    ///
    /// This differs from `asyncMap` in that it uses a `TaskGroup` to run the transform
    /// closure for all the elements of the Sequence. This allows all the transform closures
    /// to run concurrently instead of serially. Returns only when the closure has been run
    /// on all the elements of the Sequence.
    /// - Parameters:
    ///   - priority: Task priority for tasks in TaskGroup
    ///   - transform: An async  mapping closure. transform accepts an
    ///     element of this sequence as its parameter and returns a transformed value of
    ///     the same or of a different type.
    /// - Returns: An array containing the transformed elements of this sequence.
    public func concurrentMap<T: Sendable>(priority: TaskPriority? = nil, _ transform: @Sendable @escaping (Element) async throws -> T) async rethrows -> [T] {
        let result: ContiguousArray<(Int, T)> = try await withThrowingTaskGroup(of: (Int, T).self) { group in
            self.enumerated().forEach { element in
                group.addTask(priority: priority) {
                    let result = try await transform(element.1)
                    return (element.0, result)
                }
            }
            // Code for collating results copied from Sequence.map in Swift codebase
            let initialCapacity = underestimatedCount
            var result = ContiguousArray<(Int, T)>()
            result.reserveCapacity(initialCapacity)

            // Add elements up to the initial capacity without checking for regrowth.
            for _ in 0..<initialCapacity {
                try await result.append(group.next()!)
            }
            // Add remaining elements, if any.
            while let element = try await group.next() {
                result.append(element)
            }
            return result
        }
        // construct final array and fill in elements
        return [T](unsafeUninitializedCapacity: result.count) { buffer, count in
            for value in result {
                (buffer.baseAddress! + value.0).initialize(to: value.1)
            }
            count = result.count
        }
    }
}

#endif // compiler(>=5.5.2) && canImport(_Concurrency)
