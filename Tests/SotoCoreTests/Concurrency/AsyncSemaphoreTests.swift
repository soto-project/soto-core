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

@testable import SotoCore
import XCTest

@available(macOS 10.15, iOS 13.0, tvOS 13.0, watchOS 6.0, *)
final class AsyncSemaphoreTests: XCTestCase {
    func testSignalWait() async throws {
        let semaphore = AsyncSemaphore()
        let rt = semaphore.signal()
        XCTAssertEqual(rt, false)
        try await semaphore.wait()
    }

    func testNoWaitingTask() async throws {
        let semaphore = AsyncSemaphore(value: 1)
        let rt = semaphore.signal()
        XCTAssertEqual(rt, false)
        let rt2 = semaphore.signal()
        XCTAssertEqual(rt2, false)
        try await semaphore.wait()
    }

    func testWaitSignal() async throws {
        await withThrowingTaskGroup(of: Void.self) { group in
            let semaphore = AsyncSemaphore()
            group.addTask {
                try await semaphore.wait()
            }
            group.addTask {
                semaphore.signal()
            }
        }
    }

    func testWaitDelayedSignal() async throws {
        await withThrowingTaskGroup(of: Void.self) { group in
            let semaphore = AsyncSemaphore()
            group.addTask {
                try await semaphore.wait()
            }
            group.addTask {
                try await Task.sleep(nanoseconds: 10000)
                let rt = semaphore.signal()
                XCTAssertEqual(rt, true)
            }
        }
    }

    func testDoubleWaitSignal() async throws {
        await withThrowingTaskGroup(of: Void.self) { group in
            let semaphore = AsyncSemaphore()
            group.addTask {
                try await semaphore.wait()
            }
            group.addTask {
                try await semaphore.wait()
            }
            group.addTask {
                let rt = semaphore.signal()
                XCTAssertEqual(rt, true)
                let rt2 = semaphore.signal()
                XCTAssertEqual(rt2, true)
            }
        }
    }

    func testManySignalWait() async throws {
        await withThrowingTaskGroup(of: Void.self) { group in
            let semaphore = AsyncSemaphore()
            group.addTask {
                semaphore.signal()
                try await semaphore.wait()
                semaphore.signal()
                try await semaphore.wait()
                semaphore.signal()
                try await semaphore.wait()
            }
            group.addTask {
                semaphore.signal()
                semaphore.signal()
                semaphore.signal()
                try await semaphore.wait()
                try await semaphore.wait()
                try await semaphore.wait()
            }
            group.addTask {
                semaphore.signal()
                semaphore.signal()
                try await semaphore.wait()
                try await semaphore.wait()
                semaphore.signal()
                try await semaphore.wait()
            }
        }
    }

    func testCancellationWhileSuspended() async throws {
        let semaphore = AsyncSemaphore()
        let task = Task {
            do {
                try await semaphore.wait()
            } catch is CancellationError {
                XCTAssertEqual(semaphore.value.load(ordering: .sequentiallyConsistent), 0)
            } catch {
                XCTFail("Wrong Error")
            }
        }
        try await Task.sleep(nanoseconds: 10000)
        task.cancel()
    }

    func testCancellationBeforeWait() async throws {
        let semaphore = AsyncSemaphore()
        let task = Task {
            do {
                do {
                    try await Task.sleep(nanoseconds: 10000)
                } catch {}
                try await semaphore.wait()
            } catch is CancellationError {
                XCTAssertEqual(semaphore.value.load(ordering: .sequentiallyConsistent), 0)
            } catch {
                XCTFail("Wrong Error")
            }
        }
        task.cancel()
    }
}

#endif // compiler(>=5.5.2) && canImport(_Concurrency)
