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

import JMESPath
import NIO
import NIOHTTP1

public protocol AWSWaiterMatcher {
    func match(result: Result<Any, Error>) -> Bool
}

public struct JMESPathMatcher<Value: CustomStringConvertible>: AWSWaiterMatcher {
    let expression: Expression
    let expected: String

    public init(_ path: String, expected: Value) throws {
        self.expression = try Expression.compile(path)
        self.expected = expected.description
    }

    public func match(result: Result<Any, Error>) -> Bool {
        switch result {
        case .success(let output):
            do {
                if let result = try expression.search(object: output) as? CustomStringConvertible {
                    return expected == result.description
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

public struct JMESAnyPathMatcher<Value: CustomStringConvertible>: AWSWaiterMatcher {
    let expression: Expression
    let expected: String

    public init(_ path: String, expected: Value) throws {
        self.expression = try Expression.compile(path)
        self.expected = expected.description
    }

    public func match(result: Result<Any, Error>) -> Bool {
        switch result {
        case .success(let output):
            do {
                if let result = try expression.search(object: output, as: [Any].self) {
                    return result.first { expected == ($0 as? CustomStringConvertible)?.description } != nil
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

public struct JMESAllPathMatcher<Value: CustomStringConvertible>: AWSWaiterMatcher {
    let expression: Expression
    let expected: String

    public init(_ path: String, expected: Value) throws {
        self.expression = try Expression.compile(path)
        self.expected = expected.description
    }

    public func match(result: Result<Any, Error>) -> Bool {
        switch result {
        case .success(let output):
            do {
                if let result = try expression.search(object: output, as: [Any].self) {
                    return result.first { expected != ($0 as? CustomStringConvertible)?.description } == nil
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
            return (output as? Object)?[keyPath: self.path] == self.expected
        case .failure:
            return false
        }
    }
}

enum OptionaKeyPath<Object, Value> {
    case nonOptional(KeyPath<Object, Value>)
    case optional(KeyPath<Object, Value?>)
}

public struct AWSAnyPathMatcher<Object, Group: Collection, Value: Equatable>: AWSWaiterMatcher {
    let arrayPath: OptionaKeyPath<Object, Group>
    let elementPath: KeyPath<Group.Element, Value>
    let expected: Value

    public init(arrayPath: KeyPath<Object, Group>, elementPath: KeyPath<Group.Element, Value>, expected: Value) {
        self.arrayPath = .nonOptional(arrayPath)
        self.elementPath = elementPath
        self.expected = expected
    }

    public init(arrayPath: KeyPath<Object, Group?>, elementPath: KeyPath<Group.Element, Value>, expected: Value) {
        self.arrayPath = .optional(arrayPath)
        self.elementPath = elementPath
        self.expected = expected
    }

    public func match(result: Result<Any, Error>) -> Bool {
        switch result {
        case .success(let output):
            // get array
            let array: Group?
            switch self.arrayPath {
            case .nonOptional(let keyPath):
                array = (output as? Object)?[keyPath: keyPath]
            case .optional(let keyPath):
                array = (output as? Object)?[keyPath: keyPath]
            }
            if let array = array {
                return array.first { $0[keyPath: elementPath] == expected } != nil
            } else {
                return false
            }
        case .failure:
            return false
        }
    }
}

public struct AWSAllPathMatcher<Object, Group: Collection, Value: Equatable>: AWSWaiterMatcher {
    let arrayPath: OptionaKeyPath<Object, Group>
    let elementPath: KeyPath<Group.Element, Value>
    let expected: Value

    public init(arrayPath: KeyPath<Object, Group>, elementPath: KeyPath<Group.Element, Value>, expected: Value) {
        self.arrayPath = .nonOptional(arrayPath)
        self.elementPath = elementPath
        self.expected = expected
    }

    public init(arrayPath: KeyPath<Object, Group?>, elementPath: KeyPath<Group.Element, Value>, expected: Value) {
        self.arrayPath = .optional(arrayPath)
        self.elementPath = elementPath
        self.expected = expected
    }

    public func match(result: Result<Any, Error>) -> Bool {
        switch result {
        case .success(let output):
            // get array
            let array: Group?
            switch self.arrayPath {
            case .nonOptional(let keyPath):
                array = (output as? Object)?[keyPath: keyPath]
            case .optional(let keyPath):
                array = (output as? Object)?[keyPath: keyPath]
            }
            if let array = array {
                return array.first { $0[keyPath: elementPath] != expected } == nil
            } else {
                return false
            }
        case .failure:
            return false
        }
    }
}

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
