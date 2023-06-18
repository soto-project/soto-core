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

extension Sequence where Element: Sendable {
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

    /// Returns an array containing the results of mapping the given async closure over
    /// the sequence’s elements.
    ///
    /// This differs from `asyncMap` in that it uses a `TaskGroup` to run the transform
    /// closure for all the elements of the Sequence. This allows all the transform closures
    /// to run concurrently instead of serially. Returns only when the closure has been run
    /// on all the elements of the Sequence.
    /// - Parameters:
    ///   - maxConcurrentTasks: Maximum number of tasks to running at the same time
    ///   - priority: Task priority for tasks in TaskGroup
    ///   - transform: An async  mapping closure. transform accepts an
    ///     element of this sequence as its parameter and returns a transformed value of
    ///     the same or of a different type.
    /// - Returns: An array containing the transformed elements of this sequence.
    public func concurrentMap<T: Sendable>(maxConcurrentTasks: Int, priority: TaskPriority? = nil, _ transform: @Sendable @escaping (Element) async throws -> T) async rethrows -> [T] {
        let result: ContiguousArray<(Int, T)> = try await withThrowingTaskGroup(of: (Int, T).self) { group in
            var results = ContiguousArray<(Int, T)>()

            for (index, element) in self.enumerated() {
                if index >= maxConcurrentTasks {
                    if let result = try await group.next() {
                        results.append(result)
                    }
                }
                group.addTask(priority: priority) {
                    let result = try await transform(element)
                    return (index, result)
                }
            }

            // Add remaining elements, if any.
            while let result = try await group.next() {
                results.append(result)
            }
            return results
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
