//
//  DictionarySerializer.swift
//  AWSSDKSwift
//
//  Created by Yuki Takei on 2017/04/06.
//
//

import Foundation
import XCTest
@testable import AWSSDKSwiftCore

class SerializersTests: XCTestCase {

    struct Numbers : AWSShape {
        enum IntEnum : Int, Codable {
            case first
            case second
            case third
        }
        let integer : Int
        let float : Float
        let double : Double
        let intEnum : IntEnum

        private enum CodingKeys : String, CodingKey {
            case integer = "i"
            case float = "s"
            case double = "d"
            case intEnum = "enum"
        }
    }

    struct StringShape : AWSShape {
        enum StringEnum : String, Codable {
            case first="first"
            case second="second"
            case third="third"
            case fourth="fourth"
        }
        let string : String
        let optionalString : String?
        let stringEnum : StringEnum
    }

    struct Arrays : AWSShape {
        let arrayOfNatives : [Int]
        let arrayOfShapes : [Numbers]
    }

    struct Dictionaries : AWSShape {
        let dictionaryOfNatives : [String:Int]
        let dictionaryOfShapes : [String:StringShape]
    }

    struct Shape : AWSShape {
        let numbers : Numbers
        let stringShape : StringShape
        let arrays : Arrays

        private enum CodingKeys : String, CodingKey {
            case numbers = "Numbers"
            case stringShape = "Strings"
            case arrays = "Arrays"
        }
    }

    struct ShapeWithDictionaries : AWSShape {
        let shape : Shape
        let dicationaries : Dictionaries

        private enum CodingKeys : String, CodingKey {
            case shape = "s"
            case dicationaries = "d"
        }
    }

    var testShape : Shape {
        return Shape(numbers: Numbers(integer: 45, float: 3.4, double: 7.89234, intEnum: .second),
                              stringShape: StringShape(string: "String1", optionalString: "String2", stringEnum: .third),
                              arrays: Arrays(arrayOfNatives: [34,1,4098], arrayOfShapes: [Numbers(integer: 1, float: 1.2, double: 1.4, intEnum: .first), Numbers(integer: 3, float: 2.01, double: 1.01, intEnum: .third)]))
    }

    var testShapeWithDictionaries : ShapeWithDictionaries {
        return ShapeWithDictionaries(shape: testShape, dicationaries: Dictionaries(dictionaryOfNatives: ["first":1, "second":2, "third":3],
                                                                                          dictionaryOfShapes: ["strings":StringShape(string:"one", optionalString: "two", stringEnum: .third),
                                                                                                               "strings2":StringShape(string:"cat", optionalString: nil, stringEnum: .fourth)]))
    }

    func testSerializeToXML() {
        let shape = testShape
        let node = try! AWSXMLEncoder().encode(shape)

        let xml = node.xmlString
        let xmlToTest = "<Shape><Numbers><i>45</i><s>3.4</s><d>7.89234</d><enum>1</enum></Numbers><Strings><string>String1</string><optionalString>String2</optionalString><stringEnum>third</stringEnum></Strings><Arrays><arrayOfNatives>34</arrayOfNatives><arrayOfNatives>1</arrayOfNatives><arrayOfNatives>4098</arrayOfNatives><arrayOfShapes><i>1</i><s>1.2</s><d>1.4</d><enum>0</enum></arrayOfShapes><arrayOfShapes><i>3</i><s>2.01</s><d>1.01</d><enum>2</enum></arrayOfShapes></Arrays></Shape>"

        XCTAssertEqual(xmlToTest, xml)
    }

    func testEncodeDecodeXML() {
        do {
            let xml = try AWSXMLEncoder().encode(testShape)
            let testShape2 = try AWSXMLDecoder().decode(Shape.self, from:xml)
            let xml2 = try AWSXMLEncoder().encode(testShape2)

            XCTAssertEqual(xml.xmlString, xml2.xmlString)
        } catch {
            XCTFail(error.localizedDescription)
        }
    }

    func testEncodeDecodeDictionariesXML() {
        do {
            let xml = try AWSXMLEncoder().encode(testShapeWithDictionaries)
            let testShape2 = try AWSXMLDecoder().decode(ShapeWithDictionaries.self, from:xml)

            XCTAssertEqual(testShape2.dicationaries.dictionaryOfNatives["second"], 2)
            XCTAssertEqual(testShape2.dicationaries.dictionaryOfShapes["strings2"]?.stringEnum, .fourth)
        } catch {
            XCTFail(error.localizedDescription)
        }
    }

    func testEncodeQueryDictionary() {
        let queryDict = AWSShapeEncoder().query(testShapeWithDictionaries)

        // can't test dictionaries as we cannot guarantee member order

        XCTAssertEqual(queryDict["Shape.Arrays.ArrayOfShapes.member.2.Double"] as? Double, 1.01)
        XCTAssertEqual(queryDict["Shape.Numbers.IntEnum"] as? (Numbers.IntEnum), .second)
        XCTAssertEqual(queryDict["Shape.Arrays.ArrayOfNatives.member.2"] as? Int, 1)
        XCTAssertEqual(queryDict["Shape.StringShape.String"] as? String, "String1")
    }

    func testSerializeToDictionaryAndJSON() {
        let json = try! AWSShapeEncoder().json(testShapeWithDictionaries)
        let dict = try! JSONSerializer().serializeToDictionary(json)

        let dict2 = dict["s"] as? [String:Any]

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
        let dictionaryOfShapes = dictionaryDict?["dictionaryOfShapes"] as? [String:Any]
        let stringsDict2 = dictionaryOfShapes?["strings"] as? [String:Any]
        let stringEnum = stringsDict2?["stringEnum"] as? String
        XCTAssertEqual(stringEnum, "third")

        do {
            let shape2 = try DictionaryDecoder().decode(ShapeWithDictionaries.self, from: dict)
            XCTAssertEqual(shape2.shape.numbers.intEnum, .second)
        } catch {
            XCTFail(error.localizedDescription)
        }
    }

    static var allTests : [(String, (SerializersTests) -> () throws -> Void)] {
        return [
            ("testSerializeToXML", testSerializeToXML),
            ("testEncodeDecodeXML", testEncodeDecodeXML),
            ("testEncodeDecodeDictionariesXML", testEncodeDecodeDictionariesXML),
            ("testEncodeQueryDictionary", testEncodeQueryDictionary),
            ("testSerializeToDictionaryAndJSON", testSerializeToDictionaryAndJSON)
        ]
    }
}
