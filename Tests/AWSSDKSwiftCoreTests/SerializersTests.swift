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

        init(bool:Bool, integer:Int, float:Float, double:Double, intEnum:IntEnum) {
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

        enum IntEnum : Int, Codable {
            case first
            case second
            case third
        }
        let bool : Bool
        let integer : Int
        let float : Float
        let double : Double
        let intEnum : IntEnum
        let int8 : Int8
        let uint16 : UInt16
        let int32 : Int32
        let uint64 : UInt64

        private enum CodingKeys : String, CodingKey {
            case bool = "b"
            case integer = "i"
            case float = "s"
            case double = "d"
            case intEnum = "enum"
            case int8 = "int8"
            case uint16 = "uint16"
            case int32 = "int32"
            case uint64 = "uint64"
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
        public static var _members: [AWSShapeMember] = [
            AWSShapeMember(label: "ArrayOfNatives", location: .body(locationName: "ArrayOfNatives"), required: true, type: .list, encoding: .list(member: "member")),
            AWSShapeMember(label: "ArrayOfShapes", location: .body(locationName: "ArrayOfShapes"), required: true, type: .list)
        ]
        
        let arrayOfNatives : [Int]
        let arrayOfShapes : [Numbers]
    }

    struct Dictionaries : AWSShape {
        public static var _members: [AWSShapeMember] = [
            AWSShapeMember(label: "DictionaryOfNatives", location: .body(locationName: "Natives"), required: true, type: .list, encoding: .map(entry: "entry", key: "key", value: "value")),
            AWSShapeMember(label: "DictionaryOfShapes", location: .body(locationName: "Shapes"), required: true, type: .list, encoding: .flatMap(key: "key", value: "value"))
        ]
        let dictionaryOfNatives : [String:Int]
        let dictionaryOfShapes : [String:StringShape]

        private enum CodingKeys : String, CodingKey {
            case dictionaryOfNatives = "natives"
            case dictionaryOfShapes = "shapes"
        }
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
        let dictionaries : Dictionaries

        private enum CodingKeys : String, CodingKey {
            case shape = "s"
            case dictionaries = "d"
        }
    }

    var testShape : Shape {
        return Shape(numbers: Numbers(bool:true, integer: 45, float: 3.4, double: 7.89234, intEnum: .second),
                              stringShape: StringShape(string: "String1", optionalString: "String2", stringEnum: .third),
                              arrays: Arrays(arrayOfNatives: [34,1,4098], arrayOfShapes: [Numbers(bool:false, integer: 1, float: 1.2, double: 1.4, intEnum: .first), Numbers(bool:true, integer: 3, float: 2.01, double: 1.01, intEnum: .third)]))
    }

    var testShapeWithDictionaries : ShapeWithDictionaries {
        return ShapeWithDictionaries(shape: testShape, dictionaries: Dictionaries(dictionaryOfNatives: ["first":1, "second":2, "third":3],
                                                                                          dictionaryOfShapes: ["strings":StringShape(string:"one", optionalString: "two", stringEnum: .third),
                                                                                                               "strings2":StringShape(string:"cat", optionalString: nil, stringEnum: .fourth)]))
    }

    /// helper test function to use throughout all the decode/encode tests
    func testDecode<T : Codable>(type: T.Type, xml: String) -> T? {
        do {
            let xmlDocument = try XML.Document(data: xml.data(using: .utf8)!)
            let rootElement = xmlDocument.rootElement()
            XCTAssertNotNil(rootElement)
            return try XMLDecoder().decode(T.self, from: rootElement!)
            //let xmlElement = try XMLEncoder().encode(instance)
            //XCTAssertEqual(xml, xmlElement.xmlString)
        } catch {
            XCTFail(error.localizedDescription)
        }
        return nil
    }
    
    /// helper test function to use throughout all the decode/encode tests
    func testDecodeEncode<T : Codable>(type: T.Type, xml: String) {
        do {
            let xmlDocument = try XML.Document(data: xml.data(using: .utf8)!)
            let rootElement = xmlDocument.rootElement()
            XCTAssertNotNil(rootElement)
            let instance = try XMLDecoder().decode(T.self, from: rootElement!)
            let xmlElement = try XMLEncoder().encode(instance)
            XCTAssertEqual(xml, xmlElement.xmlString)
        } catch {
            XCTFail(error.localizedDescription)
        }
    }
    
    func testSimpleStructureDecodeEncode() {
        struct Test : Codable {
            let a : Int
            let b : String
        }
        let xml = "<Test><a>5</a><b>Hello</b></Test>"
        testDecodeEncode(type: Test.self, xml: xml)
    }
    
    func testContainingStructureDecodeEncode() {
        struct Test : Codable {
            let a : Int
            let b : String
        }
        struct Test2 : Codable {
            let t : Test
        }
        let xml = "<Test2><t><a>5</a><b>Hello</b></t></Test2>"
        testDecodeEncode(type: Test2.self, xml: xml)
    }
    
    func testEnumDecodeEncode() {
        struct Test : Codable {
            enum TestEnum : String, Codable {
                case first = "First"
                case second = "Second"
            }
            let a : TestEnum
        }
        let xml = "<Test><a>Second</a></Test>"
        testDecodeEncode(type: Test.self, xml: xml)
    }
    
    func testArrayDecodeEncode() {
        struct Test : Codable {
            let a : [Int]
        }
        let xml = "<Test><a>5</a><a>7</a></Test>"
        testDecodeEncode(type: Test.self, xml: xml)
    }
    
    func testArrayOfStructuresDecodeEncode() {
        struct Test2 : Codable {
            let b : String
        }
        struct Test : Codable {
            let a : [Test2]
        }
        let xml = "<Test><a><b>Hello</b></a><a><b>Goodbye</b></a></Test>"
        testDecodeEncode(type: Test.self, xml: xml)
    }
    
    func testDictionaryDecodeEncode() {
        struct Test : Codable {
            let a : [String:Int]
        }
        let xml = "<Test><a><first>1</first></a></Test>"
        testDecodeEncode(type: Test.self, xml: xml)
    }
    
    func testDateDecodeEncode() {
        struct Test : Codable {
            let date : Date
        }
        let xml = "<Test><date>24876876234.5</date></Test>"
        testDecodeEncode(type: Test.self, xml: xml)
    }
    
    func testDataDecodeEncode() {
        struct Test : Codable {
            let data : Data
        }
        let base64 = "Hello, world".data(using:.utf8)!.base64EncodedString()
        let xml = "<Test><data>\(base64)</data></Test>"
        testDecodeEncode(type: Test.self, xml: xml)
    }
    
    func testUrlDecodeEncode() {
        struct Test : Codable {
            let url : URL
        }
        let xml = "<Test><url>https://docs.aws.amazon.com/</url></Test>"
        testDecodeEncode(type: Test.self, xml: xml)
    }
    
    func testSerializeToXML() {
        let shape = testShape
        let node = try! XMLEncoder().encode(shape)

        let xml = node.xmlString
        let xmlToTest = "<Shape><Numbers><b>true</b><i>45</i><s>3.4</s><d>7.89234</d><enum>1</enum><int8>4</int8><uint16>5</uint16><int32>7</int32><uint64>90</uint64></Numbers><Strings><string>String1</string><optionalString>String2</optionalString><stringEnum>third</stringEnum></Strings><Arrays><arrayOfNatives>34</arrayOfNatives><arrayOfNatives>1</arrayOfNatives><arrayOfNatives>4098</arrayOfNatives><arrayOfShapes><b>false</b><i>1</i><s>1.2</s><d>1.4</d><enum>0</enum><int8>4</int8><uint16>5</uint16><int32>7</int32><uint64>90</uint64></arrayOfShapes><arrayOfShapes><b>true</b><i>3</i><s>2.01</s><d>1.01</d><enum>2</enum><int8>4</int8><uint16>5</uint16><int32>7</int32><uint64>90</uint64></arrayOfShapes></Arrays></Shape>"

        XCTAssertEqual(xmlToTest, xml)
    }

    func testDecodeFail() {
        let missingNative = "<Numbers><b>true</b><i>45</i><s>3.4</s><d>7.89234</d><enum>1</enum><int8>4</int8><uint16>5</uint16><int32>7</int32></Numbers>"
        let missingEnum = "<Numbers><b>true</b><i>45</i><s>3.4</s><d>7.89234</d></Numbers>"
        let wrongEnum = "<Strings><string>String1</string><optionalString>String2</optionalString><stringEnum>twenty</stringEnum></Strings>"
        let missingShape = "<Shape><Numbers><b>true</b><i>45</i><s>3.4</s><d>7.89234</d><enum>1</enum><int8>4</int8><uint16>5</uint16><int32>7</int32><uint64>90</uint64></Numbers><Strings><string>String1</string><optionalString>String2</optionalString><stringEnum>third</stringEnum></Strings></Shape>"
        let stringNotShape = "<Dictionaries><natives></natives><shapes><first>test</first></shapes></Dictionaries>"
        let notANumber = "<Dictionaries><natives><test>notANumber</test></natives><shapes></shapes></Dictionaries>"

        do {
            var xmlDocument = try XML.Document(data: missingNative.data(using: .utf8)!)
            XCTAssertNotNil(xmlDocument.rootElement())
            let result = try? XMLDecoder().decode(Numbers.self, from: xmlDocument.rootElement()!)
            XCTAssertNil(result)

            xmlDocument = try XML.Document(data: missingEnum.data(using: .utf8)!)
            XCTAssertNotNil(xmlDocument.rootElement())
            let result2 = try? XMLDecoder().decode(Numbers.self, from: xmlDocument.rootElement()!)
            XCTAssertNil(result2)

            xmlDocument = try XML.Document(data: wrongEnum.data(using: .utf8)!)
            XCTAssertNotNil(xmlDocument.rootElement())
            let result3 = try? XMLDecoder().decode(StringShape.self, from: xmlDocument.rootElement()!)
            XCTAssertNil(result3)

            xmlDocument = try XML.Document(data: missingShape.data(using: .utf8)!)
            XCTAssertNotNil(xmlDocument.rootElement())
            let result4 = try? XMLDecoder().decode(Shape.self, from: xmlDocument.rootElement()!)
            XCTAssertNil(result4)

            xmlDocument = try XML.Document(data: stringNotShape.data(using: .utf8)!)
            XCTAssertNotNil(xmlDocument.rootElement())
            let result5 = try? XMLDecoder().decode(Dictionaries.self, from: xmlDocument.rootElement()!)
            XCTAssertNil(result5)

            xmlDocument = try XML.Document(data: notANumber.data(using: .utf8)!)
            XCTAssertNotNil(xmlDocument.rootElement())
            let result6 = try? XMLDecoder().decode(Dictionaries.self, from: xmlDocument.rootElement()!)
            XCTAssertNil(result6)

        } catch {
            XCTFail(error.localizedDescription)
        }
    }

    func testDecodeExpandedContainers() {
        struct Shape : AWSShape {
            static let _members = [
                AWSShapeMember(label: "array", required: true, type: .list, encoding:.list(member: "member")),
                AWSShapeMember(label: "dictionary", required: true, type: .map, encoding:.map(entry: "entry", key: "key", value: "value"))
            ]
            let array : [Int]
            let dictionary : [String: Int]
        }
        let xmldata = "<Shape><array><member>3</member><member>2</member><member>1</member></array><dictionary><entry><key>one</key><value>1</value></entry><entry><key>two</key><value>2</value></entry><entry><key>three</key><value>3</value></entry></dictionary></Shape>"
        if let shape = testDecode(type: Shape.self, xml: xmldata) {
            XCTAssertEqual(shape.array[0], 3)
            XCTAssertEqual(shape.dictionary["two"], 2)
        }
    }

    func testArrayEncodingDecodeEncode() {
        struct Shape : AWSShape {
            static let _members = [AWSShapeMember(label: "array", required: true, type: .list, encoding:.list(member: "member"))]
            let array : [Int]
        }
        let xmldata = "<Shape><array><member>3</member><member>2</member><member>1</member></array></Shape>"
        testDecodeEncode(type: Shape.self, xml: xmldata)
    }
    
    func testArrayOfStructuresEncodingDecodeEncode() {
        struct Shape2 : AWSShape {
            let value : String
        }
        struct Shape : AWSShape {
            static let _members = [AWSShapeMember(label: "array", required: true, type: .list, encoding:.list(member: "member"))]
            let array : [Shape2]
        }
        let xmldata = "<Shape><array><member><value>test</value></member><member><value>test2</value></member><member><value>test3</value></member></array></Shape>"
        testDecodeEncode(type: Shape.self, xml: xmldata)
    }
    
    func testDictionaryEncodingDecodeEncode() {
        struct Shape : AWSShape {
            static let _members = [AWSShapeMember(label: "d", required: true, type: .map, encoding:.map(entry:"item", key: "key", value: "value"))]
            let d : [String:Int]
        }
        let xmldata = "<Shape><d><item><key>member</key><value>4</value></item></d></Shape>"
        testDecodeEncode(type: Shape.self, xml: xmldata)
    }
    
    func testDictionaryOfStructuresEncodingDecodeEncode() {
        struct Shape2 : AWSShape {
            let float : Float
        }
        struct Shape : AWSShape {
            static let _members = [AWSShapeMember(label: "d", required: true, type: .map, encoding:.map(entry:"item", key: "key", value: "value"))]
            let d : [String:Shape2]
        }
        let xmldata = "<Shape><d><item><key>member</key><value><float>1.5</float></value></item></d></Shape>"
        testDecodeEncode(type: Shape.self, xml: xmldata)
    }
    
    func testFlatDictionaryEncodingDecodeEncode() {
        struct Shape : AWSShape {
            static let _members = [AWSShapeMember(label: "d", required: true, type: .map, encoding:.flatMap(key: "key", value: "value"))]
            let d : [String:Int]
        }
        let xmldata = "<Shape><d><key>member</key><value>4</value></d></Shape>"
        testDecodeEncode(type: Shape.self, xml: xmldata)
    }
    
    func testEnumDictionaryEncodingDecodeEncode() {
        enum KeyEnum : String, Codable {
            case member = "member"
            case member2 = "member2"
        }
        struct Shape : AWSShape {
            static let _members = [AWSShapeMember(label: "d", required: true, type: .map, encoding:.map(entry:"item", key: "key", value: "value"))]
            let d : [KeyEnum:Int]
        }
        let xmldata = "<Shape><d><item><key>member</key><value>4</value></item></d></Shape>"
        testDecodeEncode(type: Shape.self, xml: xmldata)
    }
    
    func testEnumFlatDictionaryEncodingDecodeEncode() {
        enum KeyEnum : String, Codable {
            case member = "member"
            case member2 = "member2"
        }
        struct Shape : AWSShape {
            static let _members = [AWSShapeMember(label: "d", required: true, type: .map, encoding:.flatMap(key: "key", value: "value"))]
            let d : [KeyEnum:Int]
        }
        let xmldata = "<Shape><d><key>member</key><value>4</value></d></Shape>"
        testDecodeEncode(type: Shape.self, xml: xmldata)
    }
    
    func testEncodeDecodeXML() {
        do {
            let xml = try XMLEncoder().encode(testShape)
            let testShape2 = try XMLDecoder().decode(Shape.self, from:xml)
            let xml2 = try XMLEncoder().encode(testShape2)

            XCTAssertEqual(xml.xmlString, xml2.xmlString)
        } catch {
            XCTFail(error.localizedDescription)
        }
    }

    func testEncodeDecodeDictionariesXML() {
        do {
            let xml = try XMLEncoder().encode(testShapeWithDictionaries)
            let testShape2 = try XMLDecoder().decode(ShapeWithDictionaries.self, from:xml)

            XCTAssertEqual(testShape2.dictionaries.dictionaryOfNatives["second"], 2)
            XCTAssertEqual(testShape2.dictionaries.dictionaryOfShapes["strings2"]?.stringEnum, .fourth)
        } catch {
            XCTFail(error.localizedDescription)
        }
    }

    func testSerializeToDictionaryAndJSON() {
        let json = try! AWSShapeEncoder().json(testShapeWithDictionaries)
        let dict = try! JSONSerialization.jsonObject(with: json, options: []) as? [String: Any] ?? [:]

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
        let dictionaryOfShapes = dictionaryDict?["shapes"] as? [String:Any]
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
            ("testSimpleStructureDecodeEncode", testSimpleStructureDecodeEncode),
            ("testContainingStructureDecodeEncode", testContainingStructureDecodeEncode),
            ("testEnumDecodeEncode", testEnumDecodeEncode),
            ("testArrayDecodeEncode", testArrayDecodeEncode),
            ("testArrayOfStructuresDecodeEncode", testArrayOfStructuresDecodeEncode),
            ("testDictionaryDecodeEncode", testDictionaryDecodeEncode),
            ("testDateDecodeEncode", testDateDecodeEncode),
            ("testDataDecodeEncode", testDataDecodeEncode),
            ("testUrlDecodeEncode", testUrlDecodeEncode),
            ("testSerializeToXML", testSerializeToXML),
            ("testDecodeExpandedContainers", testDecodeExpandedContainers),
            ("testArrayEncodingDecodeEncode", testArrayEncodingDecodeEncode),
            ("testArrayOfStructuresEncodingDecodeEncode", testArrayOfStructuresEncodingDecodeEncode),
            ("testDictionaryEncodingDecodeEncode", testDictionaryEncodingDecodeEncode),
            ("testDictionaryOfStructuresEncodingDecodeEncode", testDictionaryOfStructuresEncodingDecodeEncode),
            ("testFlatDictionaryEncodingDecodeEncode", testFlatDictionaryEncodingDecodeEncode),
            ("testEnumDictionaryEncodingDecodeEncode", testEnumDictionaryEncodingDecodeEncode),
            ("testEnumFlatDictionaryEncodingDecodeEncode", testEnumFlatDictionaryEncodingDecodeEncode),

            ("testEncodeDecodeXML", testEncodeDecodeXML),
            ("testDecodeFail", testDecodeFail),
            ("testEncodeDecodeDictionariesXML", testEncodeDecodeDictionariesXML),
            ("testSerializeToDictionaryAndJSON", testSerializeToDictionaryAndJSON)
        ]
    }
}
