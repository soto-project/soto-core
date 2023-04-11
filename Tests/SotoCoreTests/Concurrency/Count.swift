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

// Count type for testing concurrency primitives
@available(macOS 10.15, iOS 13.0, tvOS 13.0, watchOS 6.0, *)
actor Count {
    var value: Int

    init(_ value: Int = 0) {
        self.value = value
    }

    func set(_ rhs: Int) {
        self.value = rhs
    }

    @discardableResult func add(_ rhs: Int) -> Int {
        self.value += rhs
        return self.value
    }

    @discardableResult func mul(_ rhs: Int) -> Int {
        self.value *= rhs
        return self.value
    }

    @discardableResult func min(_ rhs: Int) -> Int {
        self.value = Swift.min(self.value, rhs)
        return self.value
    }

    @discardableResult func max(_ rhs: Int) -> Int {
        self.value = Swift.max(self.value, rhs)
        return self.value
    }
}
