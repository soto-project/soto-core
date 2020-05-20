//===----------------------------------------------------------------------===//
//
// This source file is part of the AWSSDKSwift open source project
//
// Copyright (c) 2017-2020 the AWSSDKSwift project authors
// Licensed under Apache License v2.0
//
// See LICENSE.txt for license information
// See CONTRIBUTORS.txt for the list of AWSSDKSwift project authors
//
// SPDX-License-Identifier: Apache-2.0
//
//===----------------------------------------------------------------------===//

import XCTest
@testable import AWSSDKSwiftCore

class DictionaryEncoderTests: XCTestCase {
    
    
    func assertEqual(_ e1: Any, _ e2: Any) {
        if let number1 = e1 as? NSNumber, let number2 = e2 as? NSNumber {
            XCTAssertEqual(number1, number2)
        } else if let string1 = e1 as? NSString, let string2 = e2 as? NSString {
            XCTAssertEqual(string1, string2)
        } else if let data1 = e1 as? Data, let data2 = e2 as? Data {
            XCTAssertEqual(data1.base64EncodedString(), data2.base64EncodedString())
        } else if let date1 = e1 as? NSDate, let date2 = e2 as? NSDate {
            XCTAssertEqual(date1, date2)
        } else if let d1 = e1 as? [String:Any], let d2 = e2 as? [String:Any] {
            assertDictionaryEqual(d1, d2)
        } else if let a1 = e1 as? [Any], let a2 = e2 as? [Any] {
            assertArrayEqual(a1, a2)
        } else if let desc1 = e1 as? CustomStringConvertible, let desc2 = e2 as? CustomStringConvertible {
            XCTAssertEqual(desc1.description, desc2.description)
        }
    }
    
    func assertArrayEqual(_ a1: [Any], _ a2: [Any]) {
        XCTAssertEqual(a1.count, a2.count)
        for i in 0..<a1.count {
            assertEqual(a1[i], a2[i])
        }
    }
    
    func assertDictionaryEqual(_ d1: [String:Any], _ d2: [String:Any]) {
        XCTAssertEqual(d1.count, d2.count)
        
        for e1 in d1 {
            if let e2 = d2[e1.key] {
                assertEqual(e1.value, e2)
            } else {
                XCTFail("Missing key \(e1.key)")
            }
        }
    }
    
    func testDecode<T: Decodable>(
        type: T.Type,
        dictionary: [String: Any],
        decoder: DictionaryDecoder = DictionaryDecoder(),
        test: (T) -> ()) {
        do {
            let instance = try decoder.decode(T.self, from: dictionary)
            test(instance)
        } catch {
            XCTFail("\(error)")
        }
    }
    
    func testSimpleStructureDecodeEncode() {
        struct Test : Codable {
            let a : Int
            let b : String
        }
        let dictionary: [String:Any] = ["a":4, "b":"Hello"]
        testDecode(type: Test.self, dictionary: dictionary) {
            XCTAssertEqual($0.a, 4)
            XCTAssertEqual($0.b, "Hello")
        }
    }
    
    func testBaseTypesDecodeEncode() {
        struct Test : Codable {
            let bool : Bool
            let int : Int
            let int8 : Int8
            let int16 : Int16
            let int32 : Int32
            let int64 : Int64
            let uint : UInt
            let uint8 : UInt8
            let uint16 : UInt16
            let uint32 : UInt32
            let uint64 : UInt64
            let float : Float
            let double : Double
        }
        let dictionary: [String:Any] = ["bool":true, "int":0, "int8":1, "int16":2, "int32":-3, "int64":4, "uint":10, "uint8":11, "uint16":12, "uint32":13, "uint64":14, "float":1.25, "double":0.23]
        testDecode(type: Test.self, dictionary: dictionary) {
            XCTAssertEqual($0.bool, true)
            XCTAssertEqual($0.int, 0)
            XCTAssertEqual($0.int8, 1)
            XCTAssertEqual($0.int16, 2)
            XCTAssertEqual($0.int32, -3)
            XCTAssertEqual($0.int64, 4)
            XCTAssertEqual($0.uint, 10)
            XCTAssertEqual($0.uint8, 11)
            XCTAssertEqual($0.uint16, 12)
            XCTAssertEqual($0.uint32, 13)
            XCTAssertEqual($0.uint64, 14)
            XCTAssertEqual($0.float, 1.25)
            XCTAssertEqual($0.double, 0.23)
        }
    }
    
    func testContainingStructureDecodeEncode() {
        struct Test2 : AWSDecodableShape {
            let a : Int
            let b : String
        }
        struct Test : AWSDecodableShape {
            let t : Test2
        }
        let dictionary: [String:Any] = ["t": ["a":4, "b":"Hello"]]
        testDecode(type: Test.self, dictionary: dictionary) {
            XCTAssertEqual($0.t.a, 4)
            XCTAssertEqual($0.t.b, "Hello")
        }
    }
    
    func testEnumDecodeEncode() {
        struct Test : AWSDecodableShape {
            enum TestEnum : String, Codable {
                case first = "First"
                case second = "Second"
            }
            let a : TestEnum
        }
        let dictionary: [String:Any] = ["a":"First"]
        testDecode(type: Test.self, dictionary: dictionary) {
            XCTAssertEqual($0.a, .first)
        }
    }
    
    func testArrayDecodeEncode() {
        struct Test : AWSDecodableShape {
            let a : [Int]
        }
        let dictionary: [String:Any] = ["a":[1,2,3,4,5]]
        testDecode(type: Test.self, dictionary: dictionary) {
            XCTAssertEqual($0.a, [1,2,3,4,5])
        }
    }
    
    func testArrayOfStructuresDecodeEncode() {
        struct Test2 : AWSDecodableShape {
            let b : String
        }
        struct Test : AWSDecodableShape {
            let a : [Test2]
        }
        let dictionary: [String:Any] = ["a":[["b":"hello"], ["b":"goodbye"]]]
        testDecode(type: Test.self, dictionary: dictionary) {
            XCTAssertEqual($0.a[0].b, "hello")
            XCTAssertEqual($0.a[1].b, "goodbye")
        }
    }
    
    func testDictionaryDecodeEncode() {
        struct Test : AWSDecodableShape {
            let a : [String:Int]
        }
        let dictionary: [String:Any] = ["a":["key":45]]
        testDecode(type: Test.self, dictionary: dictionary) {
            XCTAssertEqual($0.a["key"], 45)
        }
    }
    
    func testEnumDictionaryDecodeEncode() {
        struct Test : AWSDecodableShape {
            enum TestEnum : String, Codable {
                case first = "First"
                case second = "Second"
            }
            let a : [TestEnum:Int]
        }
        // at the moment dictionaries with enums return an array.
        let dictionary: [String:Any] = ["a":["First",45]]
        testDecode(type: Test.self, dictionary: dictionary) {
            XCTAssertEqual($0.a[.first], 45)
        }
    }
    
   func testDataDecodeEncode() {
        struct Test : AWSDecodableShape {
            let data : Data
        }
        let dictionary: [String:Any] = ["data":"Hello, world".data(using:.utf8)!.base64EncodedString()]
        testDecode(type: Test.self, dictionary: dictionary) {
            XCTAssertEqual($0.data, "Hello, world".data(using:.utf8)!)
        }

        let decoder = DictionaryDecoder()
        decoder.dataDecodingStrategy = .raw

        let dictionary2: [String:Any] = ["data":"Hello, world".data(using:.utf8)!]
        testDecode(type: Test.self, dictionary: dictionary2, decoder: decoder) {
            XCTAssertEqual($0.data, "Hello, world".data(using:.utf8)!)
        }
    }
    
    func testDecodeErrors<T : Decodable>(type: T.Type, dictionary: [String:Any], decoder: DictionaryDecoder = DictionaryDecoder()) {
        do {
            _ = try DictionaryDecoder().decode(T.self, from: dictionary)
            XCTFail("Decoder did not throw an error when it should have")
        } catch {
            
        }
    }
    
    func testFloatOverflowDecodeErrors() {
        struct Test : AWSDecodableShape {
            let float : Float
        }
        let dictionary: [String:Any] = ["float":Double.infinity]
        testDecodeErrors(type: Test.self, dictionary: dictionary)
    }
    
    func testMissingKeyDecodeErrors() {
        struct Test : AWSDecodableShape {
            let a : Int
            let b : Int
        }
        let dictionary: [String:Any] = ["b":1]
        testDecodeErrors(type: Test.self, dictionary: dictionary)
    }
    
    func testInvalidValueDecodeErrors() {
        struct Test : AWSDecodableShape {
            let a : Int
        }
        let dictionary: [String:Any] = ["b":"test"]
        testDecodeErrors(type: Test.self, dictionary: dictionary)
    }
    
    func testNestedContainer() {
        struct Test : AWSDecodableShape {
            let firstname : String
            let surname : String
            let age : Int
            
            init(from decoder: Decoder) throws {
                let container = try decoder.container(keyedBy: CodingKeys.self)
                age = try container.decode(Int.self, forKey: .age)
                let fullname = try container.nestedContainer(keyedBy: AdditionalKeys.self, forKey: .name)
                firstname = try fullname.decode(String.self, forKey: .firstname)
                surname = try fullname.decode(String.self, forKey: .surname)
            }
            
            private enum CodingKeys : String, CodingKey {
                case name = "name"
                case age = "age"
            }
            
            private enum AdditionalKeys : String, CodingKey {
                case firstname = "firstname"
                case surname = "surname"
            }
        }
        
        let dictionary: [String:Any] = ["age":25, "name":["firstname":"John", "surname":"Smith"]]
        testDecode(type: Test.self, dictionary: dictionary) {
            XCTAssertEqual($0.age, 25)
            XCTAssertEqual($0.firstname, "John")
            XCTAssertEqual($0.surname, "Smith")
        }
    }
    
    func testSupercoder() {
        class Base : AWSDecodableShape {
            let a : Int
        }
        class Test : Base {
            required init(from decoder: Decoder) throws {
                let container = try decoder.container(keyedBy: CodingKeys.self)
                b = try container.decode(String.self, forKey: .b)
                let superDecoder = try container.superDecoder(forKey: .super)
                try super.init(from: superDecoder)
            }
            
            let b : String
            
            private enum CodingKeys : String, CodingKey {
                case b = "B"
                case `super` = "Super"
            }
        }
        
        let dictionary: [String:Any] = ["B":"Test", "Super":["a":648]]
        testDecode(type: Test.self, dictionary: dictionary) {
            XCTAssertEqual($0.b, "Test")
            XCTAssertEqual($0.a, 648)
        }
    }
    
    struct B: AWSDecodableShape {
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
    
    struct A: AWSDecodableShape {
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
                    "data": "hello".data(using: .utf8)!.base64EncodedString(),
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
            
        } catch DecodingError.keyNotFound(let key, _) {
            XCTAssertEqual(key.stringValue, "int8")
        } catch {
            XCTFail("\(error)")
        }
    }
}

