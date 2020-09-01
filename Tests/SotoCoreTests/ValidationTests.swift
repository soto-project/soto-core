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

@testable import SotoCore
import XCTest

class ValidationTests: XCTestCase {
    /// test validation
    func testValidationFail(_ shape: AWSEncodableShape) {
        do {
            try shape.validate()
            XCTFail()
        } catch let error as AWSClientError where error == AWSClientError.validationError {
            print(error.message ?? "")
        } catch {
            XCTFail(error.localizedDescription)
        }
    }

    func testValidationSuccess(_ shape: AWSEncodableShape) {
        do {
            try shape.validate()
        } catch {
            XCTFail(error.localizedDescription)
        }
    }

    func testNumericMinMaxValidation() {
        struct A: AWSEncodableShape {
            let size: Int?

            public func validate(name: String) throws {
                try self.validate(self.size, name: "size", parent: name, max: 100)
                try self.validate(self.size, name: "size", parent: name, min: 1)
            }
        }
        let a1 = A(size: 23)
        testValidationSuccess(a1)
        let a2 = A(size: 0)
        testValidationFail(a2)
        let a3 = A(size: 1000)
        testValidationFail(a3)
    }

    func testFloatingPointMinMaxValidation() {
        struct A: AWSEncodableShape {
            let size: Float?

            public func validate(name: String) throws {
                try self.validate(self.size, name: "size", parent: name, max: 50.0)
                try self.validate(self.size, name: "size", parent: name, min: 1.0)
            }
        }
        let a1 = A(size: 23)
        testValidationSuccess(a1)
        let a2 = A(size: 0)
        testValidationFail(a2)
        let a3 = A(size: 1000)
        testValidationFail(a3)
    }

    func testStringLengthMinMaxValidation() {
        struct A: AWSEncodableShape {
            let string: String?

            public func validate(name: String) throws {
                try self.validate(self.string, name: "string", parent: name, max: 24)
                try self.validate(self.string, name: "string", parent: name, min: 2)
            }
        }
        let a1 = A(string: "hello")
        testValidationSuccess(a1)
        let a2 = A(string: "This string is so long it will fail")
        testValidationFail(a2)
        let a3 = A(string: "a")
        testValidationFail(a3)
    }

    func testArrayLengthMinMaxValidation() {
        struct A: AWSEncodableShape {
            let numbers: [Int]?

            public func validate(name: String) throws {
                try self.validate(self.numbers, name: "numbers", parent: name, max: 4)
                try self.validate(self.numbers, name: "numbers", parent: name, min: 2)
            }
        }
        let a1 = A(numbers: [1, 2])
        testValidationSuccess(a1)
        let a2 = A(numbers: [1, 2, 3, 4, 5])
        testValidationFail(a2)
        let a3 = A(numbers: [1])
        testValidationFail(a3)
    }

    func testStringPatternValidation() {
        struct A: AWSEncodableShape {
            let string: String?

            public func validate(name: String) throws {
                try self.validate(self.string, name: "string", parent: name, pattern: "^[A-Za-z]{3}$")
            }
        }
        let a1 = A(string: "abc")
        testValidationSuccess(a1)
        let a2 = A(string: "abcd")
        testValidationFail(a2)
        let a3 = A(string: "a-c")
        testValidationFail(a3)
    }

    func testStringPattern2Validation() {
        struct A: AWSEncodableShape {
            let path: String

            public func validate(name: String) throws {
                try self.validate(self.path, name: "path", parent: name, pattern: "((/[A-Za-z0-9\\.,\\+@=_-]+)*)/")
            }
        }
        let a1 = A(path: "/hello/test/")
        testValidationSuccess(a1)
        let a2 = A(path: "hello/test")
        testValidationFail(a2)
        let a3 = A(path: "hello\\test")
        testValidationFail(a3)
        // this shouldn't really work but I had to limit it to finding a match, not the whole string matching. MediaConvert seems to assume that is it finding a match
        let a4 = A(path: "/%hello/test/")
        testValidationSuccess(a4)
    }
}
