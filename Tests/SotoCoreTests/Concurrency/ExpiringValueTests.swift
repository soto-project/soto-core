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

import Atomics
import Foundation
import Testing

@testable import SotoCore

final class ExpiringValueTests {
    /// Test value returned from closure is given back
    @Test func testValue() async throws {
        let expiringValue = ExpiringValue<Int>()
        let value = try await expiringValue.getValue {
            try await Task.sleep(nanoseconds: 1000)
            return (1, Date())
        }
        #expect(value == 1)
    }

    /// Test an expired value is updated
    @Test func testExpiredValue() async throws {
        let expiringValue = ExpiringValue<Int>(0, expires: Date())
        let value = try await expiringValue.getValue {
            try await Task.sleep(nanoseconds: 1000)
            return (1, Date())
        }
        #expect(value == 1)
    }

    /// Test when a value is just about to expire it returns current value and kicks off
    /// new task to get new value
    @Test func testJustAboutToExpireValue() async throws {
        let expiringValue = ExpiringValue<Int>(0, expires: Date() + 1, threshold: 3)
        let (stream, source) = AsyncStream<Void>.makeStream()
        let value = try await expiringValue.getValue {
            source.finish()
            try await Task.sleep(nanoseconds: 1000)
            return (1, Date())
        }
        await stream.first { _ in true }
        // test it return current value
        #expect(value == 0)
    }

    /// Test closure is not called if value has not expired
    @Test func testClosureNotCalled() async throws {
        let called = ManagedAtomic(false)
        let expiringValue = ExpiringValue<Int>(0, expires: Date.distantFuture, threshold: 1)
        let value = try await expiringValue.getValue {
            called.store(true, ordering: .relaxed)
            try await Task.sleep(nanoseconds: 1000)
            return (1, Date())
        }
        #expect(value == 0)
        #expect(called.load(ordering: .relaxed) == false)
    }

    /// Test closure is only called once even though we asked for value 100 times
    @Test func testClosureCalledOnce() async throws {
        let callCount = ManagedAtomic(0)
        let expiringValue = ExpiringValue<Int>()
        try await withThrowingTaskGroup(of: Int.self) { group in
            for _ in 0..<100 {
                group.addTask {
                    try await expiringValue.getValue {
                        callCount.wrappingIncrement(by: 1, ordering: .relaxed)
                        try await Task.sleep(nanoseconds: 100_000)
                        return (123, Date.distantFuture)
                    }
                }
            }
            for try await result in group {
                #expect(result == 123)
            }
        }
        #expect(callCount.load(ordering: .relaxed) == 1)
    }

    /// Test value returned from closure is given back
    @Test func testInitialClosure() async throws {
        let expiringValue = ExpiringValue<Int> {
            try await Task.sleep(nanoseconds: 1000)
            return (1, Date() + 3)
        }
        let value = try await expiringValue.getValue {
            (2, Date())
        }
        #expect(value == 1)
    }
}
