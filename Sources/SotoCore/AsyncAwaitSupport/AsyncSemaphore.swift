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

import Atomics
import Collections
import Foundation
import NIOConcurrencyHelpers

/// A Semaphore implementation that can be used with Swift Concurrency.
///
/// Much of this is inspired by the implementation from Gwendal Roué found
/// here https://github.com/groue/Semaphore
@available(macOS 10.15, iOS 13.0, tvOS 13.0, watchOS 6.0, *)
public final class AsyncSemaphore: @unchecked Sendable {
    class Suspension: @unchecked Sendable {
        enum State {
            case initial
            case suspended(CheckedContinuation<Void, Error>)
            case cancelled
        }

        /// suspension state
        var state: State
        /// identifier
        let uuid: UUID
        /// initialize a Suspension
        init() {
            self.state = .initial
            self.uuid = UUID()
        }
    }

    /// Semaphore value
    var value: ManagedAtomic<Int>
    /// queue of suspensions waiting on semaphore
    private var suspended: Deque<Suspension>
    /// Number of signal calls missed
    private var missedSignals: Int
    /// lock. Can only access `suspended` and `missedSignals` inside lock
    private let lock: NIOLock

    /// Initialize AsyncSemaphore
    public init(value: Int = 0) {
        self.value = .init(value)
        self.suspended = []
        self.missedSignals = 0
        self.lock = .init()
    }

    /// Signal (increments) semaphore
    /// - Returns: Returns if a task was awaken
    @discardableResult public func signal() -> Bool {
        let valueAfterSignal = self.value.wrappingIncrementThenLoad(by: 1, ordering: .sequentiallyConsistent)
        if valueAfterSignal <= 0 {
            return self.lock.withLock {
                // if value after signal is <= 0 then there should be a suspended
                // task in the suspended array. If there isn't it is because `signal`
                // in the middle of a `wait` call. In that situation increment
                // `missedSignals`
                if let suspension = suspended.popFirst() {
                    if case .suspended(let continuation) = suspension.state {
                        continuation.resume()
                    }
                } else {
                    missedSignals += 1
                }
                return true
            }
        }
        return false
    }

    ///  Wait for or decrement a semaphore
    public func wait() async throws {
        let valueAfterWait = self.value.wrappingDecrementThenLoad(by: 1, ordering: .sequentiallyConsistent)
        if valueAfterWait >= 0 {
            return
        }
        let suspension = Suspension()
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { cont in
                self.lock.withLockVoid {
                    if missedSignals > 0 {
                        // if there is a missed signal then a `signal` between the semaphore value being
                        // decremented and reaching this point
                        missedSignals -= 1
                        cont.resume()
                    } else if case .cancelled = suspension.state {
                        // if the state is cancelled, send cancellation error to continuation
                        cont.resume(throwing: CancellationError())
                    } else {
                        // set state to suspended and add to suspended array
                        suspension.state = .suspended(cont)
                        self.suspended.append(suspension)
                    }
                }
            }
        } onCancel: {
            self.lock.withLockVoid {
                if let index = self.suspended.firstIndex(where: { $0.uuid == suspension.uuid }) {
                    // if we find the suspension in the suspended array the remove and resume
                    // continuation with a cancellation error
                    if case .suspended(let cont) = suspension.state {
                        cont.resume(throwing: CancellationError())
                        self.suspended.remove(at: index)
                    }
                }
                // set state to cancelled
                suspension.state = .cancelled
                // increment semaphore value as we have reduced the number of tasks
                // waiting on this semaphore
                self.value.wrappingIncrement(by: 1, ordering: .sequentiallyConsistent)
            }
        }
    }
}

#endif // compiler(>=5.5.2) && canImport(_Concurrency)
