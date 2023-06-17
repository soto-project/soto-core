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

import Foundation
import Logging

actor ExpiringValue<T> {
    enum State {
        case noValue
        case waitingOnValue(Task<T, Error>)
        case withValue(T, Date)
        case withValueAndWaiting(T, Date, Task<T, Error>)
    }

    var state: State
    let threshold: TimeInterval

    init(threshold: TimeInterval = 2) {
        self.threshold = threshold
        self.state = .noValue
    }

    init(_ initialValue: T, threshold: TimeInterval = 2) {
        self.threshold = threshold
        self.state = .withValue(initialValue, Date.distantPast)
    }

    func getValue(getExpiringValue: @escaping @Sendable () async throws -> (T, Date)) async throws -> T {
        switch self.state {
        case .noValue:
            let task = self.getValueTask(getExpiringValue)
            self.state = .waitingOnValue(task)
            return try await task.value

        case .waitingOnValue(let task):
            return try await task.value

        case .withValue(let value, let expires):
            if expires.timeIntervalSinceNow < 0 {
                let task = self.getValueTask(getExpiringValue)
                self.state = .waitingOnValue(task)
                return try await task.value
            } else if expires.timeIntervalSinceNow < self.threshold {
                let task = self.getValueTask(getExpiringValue)
                self.state = .withValueAndWaiting(value, expires, task)
                return value
            } else {
                return value
            }

        case .withValueAndWaiting(let value, let expires, let task):
            if expires.timeIntervalSinceNow < 0 {
                return try await task.value
            } else {
                return value
            }
        }
    }

    func getValueTask(_ getExpiringValue: @escaping @Sendable () async throws -> (T, Date)) -> Task<T, Error> {
        return Task {
            let (value, expires) = try await getExpiringValue()
            self.state = .withValue(value, expires)
            return value
        }
    }
}
