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
/// Waiting on this semaphore will not stall the underlying thread
///
/// Much of this is inspired by the implementation from Gwendal Roué found
/// here https://github.com/groue/Semaphore. It manages to avoid the recursive
/// lock by decrementing the semaphore counter inside the withTaskCancellationHandler
/// function.
@available(macOS 10.15, iOS 13.0, tvOS 13.0, watchOS 6.0, *)
public final class AsyncSemaphore: @unchecked Sendable {
    static let idGenerator = ManagedAtomic(0)
    struct Suspension: Sendable {
        let continuation: UnsafeContinuation<Void, Error>
        let id: Int

        init(_ continuation: UnsafeContinuation<Void, Error>, id: Int) {
            self.continuation = continuation
            self.id = id
        }
    }

    /// Semaphore value
    var value: Int
    /// queue of suspensions waiting on semaphore
    private var suspended: Deque<Suspension>
    /// lock. Can only access `suspended`
    private let lock: NIOLock

    /// Initialize AsyncSemaphore
    public init(value: Int = 0) {
        self.value = .init(value)
        self.suspended = []
        self.lock = .init()
    }

    /// Signal (increments) semaphore
    /// - Returns: Returns if a task was awaken
    @discardableResult public func signal() -> Bool {
        self.lock.lock()
        self.value += 1
        if self.value <= 0 {
            // if value after signal is <= 0 then there should be a suspended
            // task in the suspended array.
            if let suspension = suspended.popFirst() {
                self.lock.unlock()
                suspension.continuation.resume()
            } else {
                self.lock.unlock()
                fatalError("Cannot have a negative semaphore value without values in the suspension array")
            }
            return true
        } else {
            self.lock.unlock()
        }
        return false
    }

    ///  Wait for or decrement a semaphore
    public func wait() async throws {
        let id = Self.idGenerator.loadThenWrappingIncrement(by: 1, ordering: .relaxed)
        try await withTaskCancellationHandler {
            self.lock.lock()
            self.value -= 1
            if self.value >= 0 {
                self.lock.unlock()
                return
            }
            try await withUnsafeThrowingContinuation { (cont: UnsafeContinuation<Void, Error>) in
                if Task.isCancelled {
                    self.value += 1
                    self.lock.unlock()
                    // if the state is cancelled, send cancellation error to continuation
                    cont.resume(throwing: CancellationError())
                } else {
                    // set state to suspended and add to suspended array
                    self.suspended.append(.init(cont, id: id))
                    self.lock.unlock()
                }
            }
        } onCancel: {
            self.lock.lock()
            if let index = self.suspended.firstIndex(where: { $0.id == id }) {
                // if we find the suspension in the suspended array the remove and resume
                // continuation with a cancellation error
                self.value += 1
                let suspension = self.suspended.remove(at: index)
                self.lock.unlock()
                suspension.continuation.resume(throwing: CancellationError())
            } else {
                self.lock.unlock()
            }
        }
    }
}

#endif // compiler(>=5.5.2) && canImport(_Concurrency)
