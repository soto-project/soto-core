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

import SotoCore
import XCTest

@available(macOS 10.15, iOS 13.0, tvOS 13.0, watchOS 6.0, *)
final class MapTests: XCTestCase {
    func testConcurrentMap() async throws {
        let array = Array(0..<800)
        let result = try await array.concurrentMap { value -> Int in
            try await Task.sleep(nanoseconds: UInt64.random(in: 1000..<100_000))
            return value
        }

        XCTAssertEqual(result, array)
    }

    func testConcurrentMapWithString() async throws {
        let array = Array(0..<800)
        let result = try await array.concurrentMap { value -> String in
            try await Task.sleep(nanoseconds: UInt64.random(in: 1000..<100_000))
            return String(value)
        }

        XCTAssertEqual(result, array.map { String($0) })
    }

    func testConcurrentMapConcurrency() async throws {
        let count = Count(0)
        let maxCount = Count(0)

        let array = Array(0..<800)
        let result = try await array.concurrentMap { value -> Int in
            let c = await count.add(1)
            await maxCount.max(c)
            try await Task.sleep(nanoseconds: UInt64.random(in: 1000..<100_000))
            await count.add(-1)
            return value
        }

        XCTAssertEqual(result, array)
        let maxValue = await maxCount.value
        XCTAssertGreaterThan(maxValue, 1)
    }

    func testConcurrentMapConcurrencyWithMaxTasks() async throws {
        let count = Count(0)
        let maxCount = Count(0)

        let array = Array(0..<800)
        let result = try await array.concurrentMap(maxConcurrentTasks: 4) { value -> Int in
            let c = await count.add(1)
            await maxCount.max(c)
            try await Task.sleep(nanoseconds: UInt64.random(in: 1000..<100_000))
            await count.add(-1)
            return value
        }

        XCTAssertEqual(result, array)
        let maxValue = await maxCount.value
        XCTAssertLessThanOrEqual(maxValue, 4)
        XCTAssertGreaterThan(maxValue, 1)
    }

    func testConcurrentMapErrorThrowing() async throws {
        struct TaskError: Error {}

        do {
            _ = try await(1...8).concurrentMap { element -> Int in
                if element == 4 {
                    throw TaskError()
                }
                return element
            }
            XCTFail("Should have failed")
        } catch is TaskError {
        } catch {
            XCTFail("Error: \(error)")
        }
    }

    func testConcurrentMapCancellation() async throws {
        let count = Count(1)

        let array = Array((1...8).reversed())
        let task = Task {
            _ = try await array.concurrentMap { value -> Int in
                try await Task.sleep(nanoseconds: numericCast(value) * 1000 * 100)
                await count.mul(value)
                return value
            }
        }
        try await Task.sleep(nanoseconds: 1 * 1000 * 100)
        task.cancel()
        let value = await count.value
        XCTAssertNotEqual(value, 1 * 2 * 3 * 4 * 5 * 6 * 7 * 8)
    }
}

#endif // compiler(>=5.5.2) && canImport(_Concurrency)
