//
//  ValidationTests.swift
//  AWSSDKSwiftCoreTests
//
//  Created by Adam Fowler 2019/08/22
//

import Foundation
import XCTest
@testable import AWSSDKSwiftCore

class ValidationTests: XCTestCase {
    
    /// test validation
    func testValidationFail(_ shape: AWSShape) {
        do {
            try shape.validate()
            XCTFail()
        } catch AWSClientError.validationError(let message) {
            print(message ?? "")
        } catch {
            XCTFail(error.localizedDescription)
        }
    }
    
    func testValidationSuccess(_ shape: AWSShape) {
        do {
            try shape.validate()
        } catch {
            XCTFail(error.localizedDescription)
        }
    }
    
    func testNumericMinMaxValidation() {
        struct A: AWSShape {
            let size: Int
            
            public func validate(name: String) throws {
                try validate(size, name:"size", parent: name, max: 100)
                try validate(size, name:"size", parent: name, min: 1)
            }
        }
        let a1 = A(size:23)
        testValidationSuccess(a1)
        let a2 = A(size: 0)
        testValidationFail(a2)
        let a3 = A(size: 1000)
        testValidationFail(a3)
    }
    
    func testStringLengthMinMaxValidation() {
        struct A: AWSShape {
            let string: String
            
            public func validate(name: String) throws {
                try validate(string, name:"string", parent: name, max: 24)
                try validate(string, name:"string", parent: name, min: 2)
            }
        }
        let a1 = A(string:"hello")
        testValidationSuccess(a1)
        let a2 = A(string: "This string is so long it will fail")
        testValidationFail(a2)
        let a3 = A(string: "a")
        testValidationFail(a3)
    }
    
    func testArrayLengthMinMaxValidation() {
        struct A: AWSShape {
            let numbers: [Int]
            
            public func validate(name: String) throws {
                try validate(numbers, name:"numbers", parent: name, max: 4)
                try validate(numbers, name:"numbers", parent: name, min: 2)
            }
        }
        let a1 = A(numbers:[1,2])
        testValidationSuccess(a1)
        let a2 = A(numbers: [1,2,3,4,5])
        testValidationFail(a2)
        let a3 = A(numbers: [1])
        testValidationFail(a3)
    }
    
    func testStringPatternValidation() {
        struct A: AWSShape {
            let string: String
            
            public func validate(name: String) throws {
                try validate(string, name:"string", parent: name, pattern: "^[A-Za-z]{3}$")
            }
        }
        let a1 = A(string:"abc")
        testValidationSuccess(a1)
        let a2 = A(string: "abcd")
        testValidationFail(a2)
        let a3 = A(string: "a-c")
        testValidationFail(a3)
    }
    
    func testStringPattern2Validation() {
        struct A: AWSShape {
            let path: String
            
            public func validate(name: String) throws {
                try validate(path, name:"path", parent: name, pattern: "((/[A-Za-z0-9\\.,\\+@=_-]+)*)/")
            }
        }
        let a1 = A(path:"/hello/test/")
        testValidationSuccess(a1)
        let a2 = A(path: "hello/test")
        testValidationFail(a2)
        let a3 = A(path: "hello\\test")
        testValidationFail(a3)
        // this shouldn't really work but I had to limit it to finding a match, not the whole string matching. MediaConvert seems to assume that is it finding a match
        let a4 = A(path:"/%hello/test/")
        testValidationSuccess(a4)
    }
    
    static var allTests : [(String, (ValidationTests) -> () throws -> Void)] {
        return [
            ("testNumericMinMaxValidation", testNumericMinMaxValidation),
            ("testStringLengthMinMaxValidation", testStringLengthMinMaxValidation),
            ("testArrayLengthMinMaxValidation", testArrayLengthMinMaxValidation),
            ("testStringPatternValidation", testStringPatternValidation),
            ("testStringPattern2Validation", testStringPattern2Validation),
        ]
    }
}

