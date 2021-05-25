//===----------------------------------------------------------------------===//
//
// This source file is part of the Soto for AWS open source project
//
// Copyright (c) 2017-2020 the Soto project authors
// Licensed under Apache License v2.0
//
// See LICENSE.txt for license information
// See CONTRIBUTORS.txt for the list of Soto project authors
//
// SPDX-License-Identifier: Apache-2.0
//
//===----------------------------------------------------------------------===//

import NIO

public protocol AWSWaiterMatcher {
    func match(result: Result<Any, Error>) -> Bool
}

public struct AWSPathMatcher<Object, Value: Equatable>: AWSWaiterMatcher {
    let path: KeyPath<Object, Value>
    let expected: Value

    public init(path: KeyPath<Object, Value>, expected: Value) {
        self.path = path
        self.expected = expected
    }
    
    public func match(result: Result<Any, Error>) -> Bool {
        switch result {
        case .success(let output):
            return (output as? Object)?[keyPath: path] == expected
        case.failure:
            return false
        }
    }
}

public struct AWSSuccessMatcher: AWSWaiterMatcher {
    public func match(result: Result<Any, Error>) -> Bool {
        switch result {
        case .success:
            return true
        case.failure:
            return false
        }
    }
}

public struct AWSErrorMatcher: AWSWaiterMatcher {
    let expected: AWSErrorType

    public init(_ expected: AWSErrorType) {
        self.expected = expected
    }
    
    public func match(result: Result<Any, Error>) -> Bool {
        switch result {
        case .success:
            return false
        case.failure(let error):
            return (error as? AWSErrorType)?.errorCode == expected.errorCode
        }
    }
}
