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

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif
import Logging

/// Type holding a value and an expiration value.
///
/// When accessing the value you have to provide a closure that will update the
/// value if it has expired or is about to expire. The type ensures there is only
/// ever one value update running at any one time. If an update is already running
/// when you call `getValue` it will wait on the current update function to finish.
actor ExpiringValue<T: Sendable> {
    enum State {
        /// No value is stored
        case noValue
        /// Initial call waiting on a value to be generated. Cannot use `waitingOnValue`` in
        /// initial call as it means we would have to setup it up before all stored properties
        /// have been initialized
        case initialWaitingOnValue(Task<(T, Date), Error>)
        /// Waiting on a value to be generated
        case waitingOnValue(Task<T, Error>)
        /// Is holding a value
        case withValue(T, Date)
        /// Is holding a value, and there is a task in progress to update it
        case withValueAndWaiting(T, Date, Task<T, Error>)
        /// Error
        case error(Error)
    }

    var state: State
    let threshold: TimeInterval

    init(threshold: TimeInterval = 2) {
        self.threshold = threshold
        self.state = .noValue
    }

    init(_ initialValue: T, expires: Date, threshold: TimeInterval = 2) {
        self.threshold = threshold
        self.state = .withValue(initialValue, expires)
    }

    init(threshold: TimeInterval = 2, getExpiringValue: @escaping @Sendable () async throws -> (T, Date)) {
        self.threshold = threshold
        let task = Task {
            try await getExpiringValue()
        }
        self.state = .initialWaitingOnValue(task)
    }

    func getValue(getExpiringValue: @escaping @Sendable () async throws -> (T, Date)) async throws -> T {
        let task: Task<T, Error>
        switch self.state {
        case .noValue:
            task = try self.getValueTask(getExpiringValue)
            self.state = .waitingOnValue(task)

        case .initialWaitingOnValue(let task):
            return try await withTaskCancellationHandler {
                switch await task.result {
                case .success(let result):
                    self.state = .withValue(result.0, result.1)
                    return result.0
                case .failure(let error):
                    self.state = .error(error)
                    throw error
                }
            } onCancel: {
                task.cancel()
            }

        case .waitingOnValue(let waitingOnTask):
            task = waitingOnTask

        case .withValue(let value, let expires):
            if expires.timeIntervalSinceNow < 0 {
                // value has expired, create new task to update value and
                // return the result of that task
                task = try self.getValueTask(getExpiringValue)
                self.state = .waitingOnValue(task)
            } else if expires.timeIntervalSinceNow < self.threshold {
                // value is about to expire, create new task to update value and
                // return current value
                let task = try self.getValueTask(getExpiringValue)
                self.state = .withValueAndWaiting(value, expires, task)
                return value
            } else {
                return value
            }

        case .withValueAndWaiting(let value, let expires, let waitingOnTask):
            if expires.timeIntervalSinceNow < 0 {
                // as value has expired wait for task to finish and return result
                task = waitingOnTask
            } else {
                // value hasn't expired so return current value
                return value
            }

        case .error(let error):
            throw error
        }
        return try await withTaskCancellationHandler {
            switch await task.result {
            case .success(let value):
                return value
            case .failure(let error):
                self.state = .error(error)
                throw error
            }
        } onCancel: {
            task.cancel()
        }
    }

    /// Create task that will return a new version of the value and a date it will expire
    /// - Parameter getExpiringValue: Function return value and expiration date
    func getValueTask(_ getExpiringValue: @escaping @Sendable () async throws -> (T, Date)) throws -> Task<T, Error> {
        try Task.checkCancellation()
        return Task {
            let (value, expires) = try await getExpiringValue()
            self.state = .withValue(value, expires)
            return value
        }
    }

    func cancel() {
        switch self.state {
        case .initialWaitingOnValue(let task):
            task.cancel()
        case .waitingOnValue(let task), .withValueAndWaiting(_, _, let task):
            task.cancel()
        default:
            break
        }
    }
}
