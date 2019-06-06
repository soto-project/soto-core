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
    
    let a = A(b: B(int: 1,
                   int8: 2,
                   int16: 3,
                   int32: 4,
                   int64: 5,
                   uint: 6,
                   uint8: 7,
                   uint16: 8,
                   uint32: 9,
                   uint64: 1234567890,
                   double: 0.5,
                   float: 0.6,
                   string: "string",
                   data: "hello".data(using: .utf8)!,
                   bool: true,
                   optional: "goodbye"),
              dictionary: ["foo": "bar"],
              array: ["a", "b", "c"])

    func testEncode() {
        do {
            let encoded = try DictionaryEncoder().encode(a)
            let b = encoded["b"] as? [String:Any]
            
            XCTAssertNotNil(b)
            XCTAssertEqual(b!["int"] as? Int, 1)
            XCTAssertEqual(b!["int8"] as? Int8, 2)
            XCTAssertEqual(b!["int16"] as? Int16, 3)
            XCTAssertEqual(b!["int32"] as? Int32, 4)
            XCTAssertEqual(b!["int64"] as? Int64, 5)
            XCTAssertEqual(b!["uint"] as? UInt, 6)
            XCTAssertEqual(b!["uint8"] as? UInt8, 7)
            XCTAssertEqual(b!["uint16"] as? UInt16, 8)
            XCTAssertEqual(b!["uint32"] as? UInt32, 9)
            XCTAssertEqual(b!["uint64"] as? UInt64, 1234567890)
            XCTAssertEqual(b!["double"] as? Double, 0.5)
            XCTAssertEqual(b!["float"] as? Float, 0.6)
            XCTAssertEqual(b!["string"] as? String, "string")
            let data = b!["data"] as? Data
            XCTAssertNotNil(data)
            XCTAssertEqual(String(data: data!, encoding: .utf8), "hello")
            XCTAssertEqual(b!["optional"] as? String, "goodbye")
            XCTAssertEqual(b!["bool"] as? Bool, true)
            let dictionary = encoded["dictionary"] as? [String:Any]
            XCTAssertNotNil(dictionary)
            XCTAssertEqual(dictionary!["foo"] as? String, "bar")
            let array = encoded["array"] as? [Any]
            XCTAssertNotNil(array)
            XCTAssertEqual(array![1] as? String, "b")

        } catch {
            XCTFail(error.localizedDescription)
        }
    }
    
    func testEncodeDecode() {
        do {
            let encoded = try DictionaryEncoder().encode(a)
            let decoded = try DictionaryDecoder().decode(A.self, from: encoded)
            
            XCTAssertEqual(a.b.int, decoded.b.int)
            XCTAssertEqual(a.b.int8, decoded.b.int8)
            XCTAssertEqual(a.b.int16, decoded.b.int16)
            XCTAssertEqual(a.b.int32, decoded.b.int32)
            XCTAssertEqual(a.b.int64, decoded.b.int64)
            XCTAssertEqual(a.b.uint, decoded.b.uint)
            XCTAssertEqual(a.b.uint8, decoded.b.uint8)
            XCTAssertEqual(a.b.uint16, decoded.b.uint16)
            XCTAssertEqual(a.b.uint32, decoded.b.uint32)
            XCTAssertEqual(a.b.uint64, decoded.b.uint64)
            XCTAssertEqual(a.b.float, decoded.b.float)
            XCTAssertEqual(a.b.double, decoded.b.double)
            XCTAssertEqual(a.b.string, decoded.b.string)
            XCTAssertEqual(a.b.optional, decoded.b.optional)
            XCTAssertEqual(a.b.bool, decoded.b.bool)
            XCTAssertEqual(a.dictionary, decoded.dictionary)
            XCTAssertEqual(a.array, decoded.array)

        } catch {
            XCTFail(error.localizedDescription)
        }
    }
    
    static var allTests : [(String, (DictionaryDecoderTests) -> () throws -> Void)] {
        return [
            ("testDecode", testDecode),
            ("testDecodeFail", testDecodeFail),
            ("testEncode", testEncode),
            ("testEncodeDecode", testEncodeDecode)
        ]
    }
}
