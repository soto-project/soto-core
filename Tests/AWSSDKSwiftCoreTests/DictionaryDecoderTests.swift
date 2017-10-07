//
//  DictionaryDecoder.swift
//  AWSSDKSwiftCorePackageDescription
//
//  Created by Yuki Takei on 2017/10/08.
//

import Foundation
import XCTest
@testable import AWSSDKSwiftCore

class DictionaryDecoderTests: XCTestCase {
    
    struct B: Codable {
        let int: Int
        let double: Double
        let float: Double
        let string: String
        let data: Data
        let bool: Bool
        let optional: String?
    }
    
    struct A: Codable {
        let b: B
        let dictionary: [String: String]
        let array: [String]
    }
    
    func testDecode() {
        do {
            let dictionary: [String: Any] = [
                "b": [
                    "int": 1,
                    "double": 2.0,
                    "float": 3.0,
                    "string": "hello",
                    "data": "hello".data(using: .utf8)!,
                    "bool": true,
                    "optional": "hello"
                ],
                "dictionary": ["foo": "bar"],
                "array": ["a", "b", "c"]
            ]
            
            let a = try DictionaryDecoder().decode(A.self, from: dictionary)
            
            XCTAssertEqual(a.b.int, 1)
            XCTAssertEqual(a.b.double, 2.0)
            XCTAssertEqual(a.b.float, 3.0)
            XCTAssertEqual(a.b.string, "hello")
            XCTAssertEqual(a.b.data, "hello".data(using: .utf8))
            XCTAssertEqual(a.b.bool, true)
            XCTAssertEqual(a.b.optional, "hello")
            XCTAssertEqual(a.dictionary, ["foo": "bar"])
            XCTAssertEqual(a.array, ["a", "b", "c"])
            
        } catch {
            XCTFail("\(error)")
        }
    }
    
    func testDecodeFail() {
        do {
            let dictionary: [String: Any] = [
                "b": [
                    "int": 1,
                    "float": 3.0,
                    "string": "hello",
                    "data": "hello".data(using: .utf8)!,
                    "bool": true,
                    "optional": "hello"
                ],
                "dictionary": ["foo": "bar"],
                "array": ["a", "b", "c"]
            ]
            
            let _ = try DictionaryDecoder().decode(A.self, from: dictionary)
            XCTFail("Never reached here")
            
        } catch DecodingError.keyNotFound(let key) {
            XCTAssertEqual(key.0.stringValue, "double")
        } catch {
            XCTFail("\(error)")
        }
    }
    
    static var allTests : [(String, (DictionaryDecoderTests) -> () throws -> Void)] {
        return [
            ("testDecode", testDecode),
            ("testDecodeFail", testDecodeFail)
        ]
    }
}
