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
        let int8: Int8
        let int16: Int16
        let int32: Int32
        let int64: Int64
        let uint: UInt
        let uint8: UInt8
        let uint16: UInt16
        let uint32: UInt32
        let uint64: UInt64
        let double: Double
        let float: Float
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
                    "int": Int.max,
                    "int8": -(Int8.max),
                    "int16": -(Int16.max),
                    "int32": -(Int32.max),
                    "int64": -(Int64.max),
                    "uint": UInt.max,
                    "uint8": UInt8.max,
                    "uint16": UInt16.max,
                    "uint32": UInt32.max,
                    "uint64": UInt64.max,
                    "double": Double.greatestFiniteMagnitude,
                    "float": Float.greatestFiniteMagnitude,
                    "string": "hello",
                    "data": "hello".data(using: .utf8)!,
                    "bool": true,
                    "optional": "hello"
                ],
                "dictionary": ["foo": "bar"],
                "array": ["a", "b", "c"]
            ]
            
            let a = try DictionaryDecoder().decode(A.self, from: dictionary)
            
            XCTAssertEqual(a.b.int, 9223372036854775807)
            XCTAssertEqual(a.b.int8, -127)
            XCTAssertEqual(a.b.int16, -32767)
            XCTAssertEqual(a.b.int32, -2147483647)
            XCTAssertEqual(a.b.int64, -9223372036854775807)
            XCTAssertEqual(a.b.uint, 18446744073709551615)
            XCTAssertEqual(a.b.uint8, 255)
            XCTAssertEqual(a.b.uint16, 65535)
            XCTAssertEqual(a.b.uint32, 4294967295)
            XCTAssertEqual(a.b.uint64, 18446744073709551615)
            XCTAssertEqual(a.b.double, 1.7976931348623157E+308)
            XCTAssertEqual(a.b.float, 3.40282347E+38)
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
            
            let _ = try DictionaryDecoder().decode(A.self, from: dictionary)
            XCTFail("Never reached here")
            
        } catch DecodingError.keyNotFound(let key) {
            XCTAssertEqual(key.0.stringValue, "int8")
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
