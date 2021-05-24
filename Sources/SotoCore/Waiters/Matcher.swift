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

protocol AWSMatcher {
    func match(result: Result<Any, Error>) -> Bool
}

struct AWSOutputMatcher<Value: Equatable>: AWSMatcher {
    let path: AnyKeyPath
    let expected: Value

    func match(result: Result<Any, Error>) -> Bool {
        switch result {
        case .success(let output):
            return (output[keyPath: path] as? Value) == expected
        case.failure:
            return false
        }
    }
}

struct AWSSuccessMatcher: AWSMatcher {
    func match(result: Result<Any, Error>) -> Bool {
        switch result {
        case .success:
            return true
        case.failure:
            return false
        }
    }
}

struct AWSErrorMatcher: AWSMatcher {
    let expected: AWSErrorType

    func match(result: Result<Any, Error>) -> Bool {
        switch result {
        case .success:
            return false
        case.failure(let error):
            return (error as? AWSErrorType)?.errorCode == expected.errorCode
        }
    }
}
