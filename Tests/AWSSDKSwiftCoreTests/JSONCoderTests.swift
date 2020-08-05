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

@testable import AWSSDKSwiftCore
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
        return ShapeWithDictionaries(shape: testShape, dictionaries: Dictionaries(
            dictionaryOfNatives: ["first": 1, "second": 2, "third": 3],
            dictionaryOfShapes: [
                "strings": StringShape(string: "one", optionalString: "two", stringEnum: .third),
                "strings2": StringShape(string: "cat", optionalString: nil, stringEnum: .fourth),
            ]
        ))
    }

    func testSerializeToDictionaryAndJSON() {
        let json = try! testShapeWithDictionaries.encodeAsJSON()
        let dict = try! JSONSerialization.jsonObject(with: json, options: []) as? [String: Any] ?? [:]

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
}
