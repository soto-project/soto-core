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

import NIOCore
@testable import SotoCore
import XCTest

class JSONCoderTests: XCTestCase {
    struct Numbers: AWSDecodableShape & AWSEncodableShape {
        init(bool: Bool, integer: Int, float: Float, double: Double, intEnum: IntEnum) {
            self.bool = bool
            self.integer = integer
            self.float = float
            self.double = double
            self.intEnum = intEnum
            self.int8 = 4
            self.uint16 = 5
            self.int32 = 7
            self.uint64 = 90
        }

        enum IntEnum: Int, Codable {
            case first
            case second
            case third
        }

        let bool: Bool
        let integer: Int
        let float: Float
        let double: Double
        let intEnum: IntEnum
        let int8: Int8
        let uint16: UInt16
        let int32: Int32
        let uint64: UInt64

        private enum CodingKeys: String, CodingKey {
            case bool = "b"
            case integer = "i"
            case float = "s"
            case double = "d"
            case intEnum = "enum"
            case int8
            case uint16
            case int32
            case uint64
        }
    }

    struct StringShape: AWSDecodableShape & AWSEncodableShape {
        enum StringEnum: String, Codable {
            case first
            case second
            case third
            case fourth
        }

        let string: String
        let optionalString: String?
        let stringEnum: StringEnum
    }

    struct Arrays: AWSDecodableShape & AWSEncodableShape {
        let arrayOfNatives: [Int]
        let arrayOfShapes: [Numbers]
    }

    struct Dictionaries: AWSDecodableShape & AWSEncodableShape {
        let dictionaryOfNatives: [String: Int]
        let dictionaryOfShapes: [String: StringShape]

        private enum CodingKeys: String, CodingKey {
            case dictionaryOfNatives = "natives"
            case dictionaryOfShapes = "shapes"
        }
    }

    struct Shape: AWSDecodableShape & AWSEncodableShape {
        let numbers: Numbers
        let stringShape: StringShape
        let arrays: Arrays

        private enum CodingKeys: String, CodingKey {
            case numbers = "Numbers"
            case stringShape = "Strings"
            case arrays = "Arrays"
        }
    }

    struct ShapeWithDictionaries: AWSDecodableShape & AWSEncodableShape {
        let shape: Shape
        let dictionaries: Dictionaries

        private enum CodingKeys: String, CodingKey {
            case shape = "s"
            case dictionaries = "d"
        }
    }

    var testShape: Shape {
        return Shape(
            numbers: Numbers(bool: true, integer: 45, float: 3.4, double: 7.89234, intEnum: .second),
            stringShape: StringShape(string: "String1", optionalString: "String2", stringEnum: .third),
            arrays: Arrays(arrayOfNatives: [34, 1, 4098], arrayOfShapes: [Numbers(bool: false, integer: 1, float: 1.2, double: 1.4, intEnum: .first), Numbers(bool: true, integer: 3, float: 2.01, double: 1.01, intEnum: .third)])
        )
    }

    var testShapeWithDictionaries: ShapeWithDictionaries {
        return ShapeWithDictionaries(shape: self.testShape, dictionaries: Dictionaries(
            dictionaryOfNatives: ["first": 1, "second": 2, "third": 3],
            dictionaryOfShapes: [
                "strings": StringShape(string: "one", optionalString: "two", stringEnum: .third),
                "strings2": StringShape(string: "cat", optionalString: nil, stringEnum: .fourth),
            ]
        ))
    }

    /// helper test function to use throughout all the decode/encode tests
    func testEncodeDecode<T: Codable & Equatable>(object: T, expected: String) {
        do {
            let jsonData = try JSONEncoder().encode(object)
            XCTAssertEqual(jsonData, Data(expected.utf8))
            let dict = try JSONSerialization.jsonObject(with: jsonData, options: [])
            let object2 = try DictionaryDecoder().decode(T.self, from: dict)
            XCTAssertEqual(object, object2)
        } catch {
            XCTFail("\(error)")
        }
    }

    func testSerializeToDictionaryAndJSON() throws {
        var json = try self.testShapeWithDictionaries.encodeAsJSON(byteBufferAllocator: ByteBufferAllocator())
        let data = try XCTUnwrap(json.readData(length: json.readableBytes))
        let dict = try! JSONSerialization.jsonObject(with: data, options: []) as? [String: Any] ?? [:]

        let dict2 = dict["s"] as? [String: Any]

        // Member scalar
        let stringsDict = dict2?["Strings"]! as? [String: Any]
        let string = stringsDict?["string"] as? String
        XCTAssertEqual(string, "String1")

        // array member
        let arrayDict = dict2?["Arrays"] as? [String: Any]
        let nativeArray = arrayDict?["arrayOfNatives"] as? [Any]
        let value = nativeArray?[2] as? Int
        XCTAssertEqual(value, 4098)

        // dicationary member
        let dictionaryDict = dict["d"] as? [String: Any]
        let dictionaryOfShapes = dictionaryDict?["shapes"] as? [String: Any]
        let stringsDict2 = dictionaryOfShapes?["strings"] as? [String: Any]
        let stringEnum = stringsDict2?["stringEnum"] as? String
        XCTAssertEqual(stringEnum, "third")

        do {
            let shape2 = try DictionaryDecoder().decode(ShapeWithDictionaries.self, from: dict)
            XCTAssertEqual(shape2.shape.numbers.intEnum, .second)
        } catch {
            XCTFail(error.localizedDescription)
        }
    }

    func testBase64() {
        struct Test: Codable, Equatable {
            let data: AWSBase64Data
        }
        self.testEncodeDecode(object: Test(data: .data("Testing".utf8)), expected: #"{"data":"VGVzdGluZw=="}"#)
    }

    func testBase64EncodeDecode() throws {
        struct Test: Codable, Equatable {
            let data: AWSBase64Data
        }
        // self.testEncodeDecode(object: Test(data: .data("Testing".utf8)), expected: #"{"data":"VGVzdGluZw=="}"#)
        let string = """
        Lorem ipsum dolor sit amet, consectetur adipiscing elit, sed do eiusmod 
        tempor incididunt ut labore et dolore magna aliqua. Ut enim ad minim veniam, 
        quis nostrud exercitation ullamco laboris nisi ut aliquip ex ea commodo 
        consequat. Duis aute irure dolor in reprehenderit in voluptate velit esse 
        cillum dolore eu fugiat nulla pariatur. Excepteur sint occaecat cupidatat 
        non proident, sunt in culpa qui officia deserunt mollit anim id est laborum.
        """
        let test = Test(data: .data(string.utf8))
        let jsonData = try JSONEncoder().encode(test)
        let dict = try JSONSerialization.jsonObject(with: jsonData, options: [])
        let object2 = try DictionaryDecoder().decode(Test.self, from: dict)
        XCTAssertEqual([UInt8](string.utf8), object2.data.decoded())
    }
}
