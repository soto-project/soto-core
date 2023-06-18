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

import JMESPath
import NIOCore
import NIOHTTP1

/// Protocol for matchers used in waiters.
///
/// A matcher returns whether the returned value from an AWS API call matches a certain state
public protocol AWSWaiterMatcher: Sendable {
    func match(result: Result<Any, Error>) -> Bool
}

/// Match whether the value indicated by JMESPath matches an expected value
public struct JMESPathMatcher<Value: CustomStringConvertible>: AWSWaiterMatcher {
    let expression: JMESExpression
    let expected: String

    public init(_ path: String, expected: Value) throws {
        self.expression = try JMESExpression.compile(path)
        self.expected = expected.description
    }

    public func match(result: Result<Any, Error>) -> Bool {
        switch result {
        case .success(let output):
            do {
                if let searchResult = try expression.search(object: output, as: CustomStringConvertible.self) {
                    return self.expected == searchResult.description
                } else {
                    return false
                }
            } catch {
                return false
            }
        case .failure:
            return false
        }
    }
}

/// Match whether any of the values indicated by JMESPath matches an expected value
public struct JMESAnyPathMatcher<Value: CustomStringConvertible>: AWSWaiterMatcher {
    let expression: JMESExpression
    let expected: String

    public init(_ path: String, expected: Value) throws {
        self.expression = try JMESExpression.compile(path)
        self.expected = expected.description
    }

    public func match(result: Result<Any, Error>) -> Bool {
        switch result {
        case .success(let output):
            do {
                if let searchResult = try expression.search(object: output, as: [CustomStringConvertible].self) {
                    return searchResult.first { self.expected == $0.description } != nil
                } else {
                    return false
                }
            } catch {
                return false
            }
        case .failure:
            return false
        }
    }
}

/// Match whether all of the values indicated by JMESPath matches an expected value
public struct JMESAllPathMatcher<Value: CustomStringConvertible>: AWSWaiterMatcher {
    let expression: JMESExpression
    let expected: String

    public init(_ path: String, expected: Value) throws {
        self.expression = try JMESExpression.compile(path)
        self.expected = expected.description
    }

    public func match(result: Result<Any, Error>) -> Bool {
        switch result {
        case .success(let output):
            do {
                if let searchResult = try expression.search(object: output, as: [CustomStringConvertible].self) {
                    return searchResult.first { self.expected != $0.description } == nil
                } else {
                    return false
                }
            } catch {
                return false
            }
        case .failure:
            return false
        }
    }
}

/// Match whether an AWS API call was successful
public struct AWSSuccessMatcher: AWSWaiterMatcher {
    public init() {}
    public func match(result: Result<Any, Error>) -> Bool {
        switch result {
        case .success:
            return true
        case .failure:
            return false
        }
    }
}

/// Match whether an AWS API call returns a specific HTTP response code
public struct AWSErrorStatusMatcher: AWSWaiterMatcher {
    let expectedStatus: Int

    public init(_ status: Int) {
        self.expectedStatus = status
    }

    public func match(result: Result<Any, Error>) -> Bool {
        switch result {
        case .success:
            return false
        case .failure(let error as AWSErrorType):
            if let code = error.context?.responseCode.code {
                return code == self.expectedStatus
            } else {
                return false
            }
        case .failure(let error as AWSRawError):
            return error.context.responseCode.code == self.expectedStatus
        case .failure:
            return false
        }
    }
}

/// Match whether an AWS API call returns a specific error code
public struct AWSErrorCodeMatcher: AWSWaiterMatcher {
    let expectedCode: String

    public init(_ code: String) {
        self.expectedCode = code
    }

    public func match(result: Result<Any, Error>) -> Bool {
        switch result {
        case .success:
            return false
        case .failure(let error):
            return (error as? AWSErrorType)?.errorCode == self.expectedCode
        }
    }
}
