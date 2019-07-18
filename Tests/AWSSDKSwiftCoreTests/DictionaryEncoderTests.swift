//
//  DictionaryDecoder.swift
//  AWSSDKSwiftCorePackageDescription
//
//  Created by Yuki Takei on 2017/10/08.
//

import Foundation
import XCTest
@testable import AWSSDKSwiftCore

class DictionaryEncoderTests: XCTestCase {
    
    
    func assertEqual(_ e1: Any, _ e2: Any) {
        print("\(type(of:e1)) == \(type(of:e2))")
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
    
    /// helper test function to use throughout all the decode/encode tests
    func testDecodeEncode<T : Codable>(type: T.Type, dictionary: [String:Any], decoder: DictionaryDecoder = DictionaryDecoder(), encoder: DictionaryEncoder = DictionaryEncoder()) {
        do {
            let instance = try decoder.decode(T.self, from: dictionary)
            let newDictionary = try encoder.encode(instance)
            
            // check dictionaries are the same
            assertEqual(dictionary, newDictionary)
        } catch {
            XCTFail(error.localizedDescription)
        }
    }
    
    func testSimpleStructureDecodeEncode() {
        struct Test : Codable {
            let a : Int
            let b : String
        }
        let dictionary: [String:Any] = ["a":4, "b":"Hello"]
        testDecodeEncode(type: Test.self, dictionary: dictionary)
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
        testDecodeEncode(type: Test.self, dictionary: dictionary)
    }
    
    func testContainingStructureDecodeEncode() {
        struct Test2 : Codable {
            let a : Int
            let b : String
        }
        struct Test : Codable {
            let t : Test2
        }
        let dictionary: [String:Any] = ["t": ["a":4, "b":"Hello"]]
        testDecodeEncode(type: Test.self, dictionary: dictionary)
    }
    
    func testEnumDecodeEncode() {
        struct Test : Codable {
            enum TestEnum : String, Codable {
                case first = "First"
                case second = "Second"
            }
            let a : TestEnum
        }
        let dictionary: [String:Any] = ["a":"First"]
        testDecodeEncode(type: Test.self, dictionary: dictionary)
    }
    
    func testArrayDecodeEncode() {
        struct Test : Codable {
            let a : [Int]
        }
        let dictionary: [String:Any] = ["a":[1,2,3,4,5]]
        testDecodeEncode(type: Test.self, dictionary: dictionary)
    }
    
    func testArrayOfStructuresDecodeEncode() {
        struct Test2 : Codable {
            let b : String
        }
        struct Test : Codable {
            let a : [Test2]
        }
        let dictionary: [String:Any] = ["a":[["b":"hello"], ["b":"goodbye"]]]
        testDecodeEncode(type: Test.self, dictionary: dictionary)
    }
    
    func testDictionaryDecodeEncode() {
        struct Test : Codable {
            let a : [String:Int]
        }
        let dictionary: [String:Any] = ["a":["key":45]]
        testDecodeEncode(type: Test.self, dictionary: dictionary)
    }
    
    func testEnumDictionaryDecodeEncode() {
        struct Test : Codable {
            enum TestEnum : String, Codable {
                case first = "First"
                case second = "Second"
            }
            let a : [TestEnum:Int]
        }
        // at the moment dictionaries with enums return an array.
        let dictionary: [String:Any] = ["a":["First",45]]
        testDecodeEncode(type: Test.self, dictionary: dictionary)
    }
    
    func testDateDecodeEncode() {
        struct Test : Codable {
            let date : Date
        }
        let dictionary: [String:Any] = ["date":29872384673]
        testDecodeEncode(type: Test.self, dictionary: dictionary)
        
        let dateFormatter = DateFormatter()
        dateFormatter.locale = Locale(identifier: "en_US_POSIX")
        dateFormatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSS'Z'"
        
        let decoder = DictionaryDecoder()
        decoder.dateDecodingStrategy = .formatted(dateFormatter)
        let encoder = DictionaryEncoder()
        encoder.dateEncodingStrategy = .formatted(dateFormatter)
        
        let dictionary2: [String:Any] = ["date":"2001-07-21T14:31:45.100Z"]
        testDecodeEncode(type: Test.self, dictionary: dictionary2, decoder: decoder, encoder: encoder)
    }
    
    func testDataDecodeEncode() {
        struct Test : Codable {
            let data : Data
        }
        let dictionary: [String:Any] = ["data":"Hello, world".data(using:.utf8)!]
        testDecodeEncode(type: Test.self, dictionary: dictionary)
        
        let decoder = DictionaryDecoder()
        decoder.dataDecodingStrategy = .base64
        let encoder = DictionaryEncoder()
        encoder.dataEncodingStrategy = .base64
        
        let dictionary2: [String:Any] = ["data":"Hello, world".data(using:.utf8)!.base64EncodedString()]
        testDecodeEncode(type: Test.self, dictionary: dictionary2, decoder: decoder, encoder: encoder)
    }
    
    func testUrlDecodeEncode() {
        struct Test : Codable {
            let url : URL
        }
        let dictionary: [String:Any] = ["url":"www.google.com"]
        testDecodeEncode(type: Test.self, dictionary: dictionary)
    }
    
    func testDecodeErrors<T : Codable>(type: T.Type, dictionary: [String:Any], decoder: DictionaryDecoder = DictionaryDecoder()) {
        do {
            _ = try DictionaryDecoder().decode(T.self, from: dictionary)
            XCTFail("Decoder did not throw an error when it should have")
        } catch {
            
        }
    }
    
    func testFloatOverflowDecodeErrors() {
        struct Test : Codable {
            let float : Float
        }
        let dictionary: [String:Any] = ["float":Double.infinity]
        testDecodeErrors(type: Test.self, dictionary: dictionary)
    }
    
    func testMissingKeyDecodeErrors() {
        struct Test : Codable {
            let a : Int
            let b : Int
        }
        let dictionary: [String:Any] = ["b":1]
        testDecodeErrors(type: Test.self, dictionary: dictionary)
    }
    
    func testInvalidValueDecodeErrors() {
        struct Test : Codable {
            let a : Int
        }
        let dictionary: [String:Any] = ["b":"test"]
        testDecodeErrors(type: Test.self, dictionary: dictionary)
    }
    
    func testNestedContainer() {
        struct Test : Codable {
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
            
            func encode(to encoder: Encoder) throws {
                var container = encoder.container(keyedBy: CodingKeys.self)
                try container.encode(age, forKey: .age)
                var fullname = container.nestedContainer(keyedBy: AdditionalKeys.self, forKey: .name)
                try fullname.encode(firstname, forKey: .firstname)
                try fullname.encode(surname, forKey: .surname)
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
        testDecodeEncode(type: Test.self, dictionary: dictionary)
    }
    
    func testSupercoder() {
        class Base : Codable {
            let a : Int
        }
        class Test : Base {
            required init(from decoder: Decoder) throws {
                let container = try decoder.container(keyedBy: CodingKeys.self)
                b = try container.decode(String.self, forKey: .b)
                let superDecoder = try container.superDecoder(forKey: .super)
                try super.init(from: superDecoder)
            }
            
            override func encode(to encoder: Encoder) throws {
                var container = encoder.container(keyedBy: CodingKeys.self)
                try container.encode(b, forKey: .b)
                let superEncoder = container.superEncoder(forKey: .super)
                try super.encode(to: superEncoder)
            }
            let b : String
            
            private enum CodingKeys : String, CodingKey {
                case b = "B"
                case `super` = "Super"
            }
        }
        
        let dictionary: [String:Any] = ["B":"Test", "Super":["a":648]]
        testDecodeEncode(type: Test.self, dictionary: dictionary)
    }
    
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
    
    static var allTests : [(String, (DictionaryEncoderTests) -> () throws -> Void)] {
        return [
            ("testDecode", testDecode),
            ("testDecodeFail", testDecodeFail),
            ("testEncode", testEncode),
            ("testEncodeDecode", testEncodeDecode),
            ("testSimpleStructureDecodeEncode", testSimpleStructureDecodeEncode),
            ("testBaseTypesDecodeEncode", testBaseTypesDecodeEncode),
            ("testContainingStructureDecodeEncode", testContainingStructureDecodeEncode),
            ("testEnumDecodeEncode", testEnumDecodeEncode),
            ("testArrayDecodeEncode", testArrayDecodeEncode),
            ("testArrayOfStructuresDecodeEncode", testArrayOfStructuresDecodeEncode),
            ("testDictionaryDecodeEncode", testDictionaryDecodeEncode),
            ("testEnumDictionaryDecodeEncode", testEnumDictionaryDecodeEncode),
            ("testDateDecodeEncode", testDateDecodeEncode),
            ("testDataDecodeEncode", testDataDecodeEncode),
            ("testUrlDecodeEncode", testUrlDecodeEncode),
            ("testFloatOverflowDecodeErrors", testFloatOverflowDecodeErrors),
            ("testInvalidValueDecodeErrors", testInvalidValueDecodeErrors),
            ("testMissingKeyDecodeErrors", testMissingKeyDecodeErrors),
            ("testNestedContainer", testNestedContainer),
            ("testSupercoder", testSupercoder)
        ]
    }
}
