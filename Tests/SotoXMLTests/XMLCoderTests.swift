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

import Foundation
import Testing

@testable import SotoCore
@testable import SotoXML

class XMLCoderTests {
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
        Shape(
            numbers: Numbers(bool: true, integer: 45, float: 3.4, double: 7.89234, intEnum: .second),
            stringShape: StringShape(string: "String1", optionalString: "String2", stringEnum: .third),
            arrays: Arrays(
                arrayOfNatives: [34, 1, 4098],
                arrayOfShapes: [
                    Numbers(bool: false, integer: 1, float: 1.2, double: 1.4, intEnum: .first),
                    Numbers(bool: true, integer: 3, float: 2.01, double: 1.01, intEnum: .third),
                ]
            )
        )
    }

    var testShapeWithDictionaries: ShapeWithDictionaries {
        ShapeWithDictionaries(
            shape: self.testShape,
            dictionaries: Dictionaries(
                dictionaryOfNatives: ["first": 1, "second": 2, "third": 3],
                dictionaryOfShapes: [
                    "strings": StringShape(string: "one", optionalString: "two", stringEnum: .third),
                    "strings2": StringShape(string: "cat", optionalString: nil, stringEnum: .fourth),
                ]
            )
        )
    }

    /// helper test function to use throughout all the decode/encode tests
    func testDecode<T: Decodable>(type: T.Type, xml: String) -> T? {
        do {
            let xmlDocument = try XML.Document(data: xml.data(using: .utf8)!)
            let rootElement = xmlDocument.rootElement()
            #expect(rootElement != nil)
            return try XMLDecoder().decode(T.self, from: rootElement!)
            // let xmlElement = try XMLEncoder().encode(instance)
            // #expect(xml == xmlElement.xmlString)
        } catch {
            Issue.record("\(error)")
        }
        return nil
    }

    /// helper test function to use throughout all the decode/encode tests
    func testDecodeEncode<T: Codable>(type: T.Type, xml: String) {
        do {
            let xmlDocument = try XML.Document(data: xml.data(using: .utf8)!)
            let rootElement = xmlDocument.rootElement()
            #expect(rootElement != nil)
            let instance = try XMLDecoder().decode(T.self, from: rootElement!)
            let xmlElement = try XMLEncoder().encode(instance)
            #expect(xml == xmlElement?.xmlString)
        } catch {
            Issue.record("\(error)")
        }
    }

    @Test func testArrayUserProperty() {
        struct ArrayMember2: ArrayCoderProperties { static let member = "member2" }
        struct Test: Codable {
            @CustomCoding<ArrayCoder<ArrayMember2, String>> var a: [String]
        }
        let test = Test(a: ["one", "two", "three"])
        do {
            let xml = try XMLEncoder().encode(test)?.xmlString
            #expect(xml == "<Test><a><member2>one</member2><member2>two</member2><member2>three</member2></a></Test>")
        } catch {
            Issue.record("\(error)")
        }
        let xml = "<Test><a><member2>one</member2><member2>two</member2><member2>three</member2></a></Test>"
        self.testDecodeEncode(type: Test.self, xml: xml)
    }

    @Test func testOptionalDictionary() {
        struct Test: Codable {
            @OptionalCustomCoding<StandardDictionaryCoder> var a: [String: Int]?
        }
        let xml = "<Test><a><entry><key>one</key><value>1</value></entry></a></Test>"
        self.testDecodeEncode(type: Test.self, xml: xml)
        let xml2 = "<Test></Test>"
        self.testDecodeEncode(type: Test.self, xml: xml2)
    }

    @Test func testNoUserProperty() {
        struct Test: Codable {
            var a: [String]
        }
        let xml = "<Test><a>one</a><a>two</a><a>three</a></Test>"
        self.testDecodeEncode(type: Test.self, xml: xml)
    }

    @Test func testSimpleStructureDecodeEncode() {
        struct Test: Codable {
            let a: Int
            let b: String
        }
        let xml = "<Test><a>5</a><b>Hello</b></Test>"
        self.testDecodeEncode(type: Test.self, xml: xml)
    }

    @Test func testContainingStructureDecodeEncode() {
        struct Test: Codable {
            let a: Int
            let b: String
        }
        struct Test2: Codable {
            let t: Test
        }
        let xml = "<Test2><t><a>5</a><b>Hello</b></t></Test2>"
        self.testDecodeEncode(type: Test2.self, xml: xml)
    }

    @Test func testEnumDecodeEncode() {
        struct Test: Codable {
            enum TestEnum: String, Codable {
                case first = "First"
                case second = "Second"
            }

            let a: TestEnum
        }
        let xml = "<Test><a>Second</a></Test>"
        self.testDecodeEncode(type: Test.self, xml: xml)
    }

    @Test func testArrayDecodeEncode() {
        struct Test: Codable {
            let a: [Int]
        }
        let xml = "<Test><a>5</a><a>7</a></Test>"
        self.testDecodeEncode(type: Test.self, xml: xml)
    }

    @Test func testEmptyArrayDecodeEncode() {
        struct Test: Codable {
            let a: [Int]
        }
        let xml = "<Test></Test>"
        self.testDecodeEncode(type: Test.self, xml: xml)
    }

    @Test func testArrayOfStructuresDecodeEncode() {
        struct Test2: Codable {
            let b: String
        }
        struct Test: Codable {
            let a: [Test2]
        }
        let xml = "<Test><a><b>Hello</b></a><a><b>Goodbye</b></a></Test>"
        self.testDecodeEncode(type: Test.self, xml: xml)
    }

    @Test func testDictionaryDecodeEncode() {
        struct Test: Codable {
            let a: [String: Int]
        }
        let xml = "<Test><a><first>1</first></a></Test>"
        self.testDecodeEncode(type: Test.self, xml: xml)
    }

    @Test func testDataDecodeEncode() {
        struct Test: Codable {
            let data: Data
        }
        let base64 = "Hello, world".data(using: .utf8)!.base64EncodedString()
        let xml = "<Test><data>\(base64)</data></Test>"
        self.testDecodeEncode(type: Test.self, xml: xml)
    }

    @Test func testAttributeDecode() {
        struct Test: Codable {
            let type: String
        }
        let xml = "<Test type=\"Hello\" />"
        let value = self.testDecode(type: Test.self, xml: xml)
        #expect(value?.type == "Hello")
    }

    @Test func testEnumAttributeDecode() {
        enum Answer: String, Codable {
            case yes
            case no
        }
        struct Test: Codable {
            //  static let _encoding = [AWSMemberEncoding(label: "type", required: true, type: .map, encoding:.attribute)]
            let type: Answer
        }
        let xml = "<Test type=\"yes\" />"
        let value = self.testDecode(type: Test.self, xml: xml)
        #expect(value?.type == .yes)
    }

    @Test func testSerializeToXML() {
        let shape = self.testShape
        let node = try! XMLEncoder().encode(shape)

        let xml = node?.xmlString
        let xmlToTest =
            "<Shape><Numbers><b>true</b><i>45</i><s>3.4</s><d>7.89234</d><enum>1</enum><int8>4</int8><uint16>5</uint16><int32>7</int32><uint64>90</uint64></Numbers><Strings><string>String1</string><optionalString>String2</optionalString><stringEnum>third</stringEnum></Strings><Arrays><arrayOfNatives>34</arrayOfNatives><arrayOfNatives>1</arrayOfNatives><arrayOfNatives>4098</arrayOfNatives><arrayOfShapes><b>false</b><i>1</i><s>1.2</s><d>1.4</d><enum>0</enum><int8>4</int8><uint16>5</uint16><int32>7</int32><uint64>90</uint64></arrayOfShapes><arrayOfShapes><b>true</b><i>3</i><s>2.01</s><d>1.01</d><enum>2</enum><int8>4</int8><uint16>5</uint16><int32>7</int32><uint64>90</uint64></arrayOfShapes></Arrays></Shape>"

        #expect(xmlToTest == xml)
    }

    @Test func testDecodeFail() {
        let missingNative =
            "<Numbers><b>true</b><i>45</i><s>3.4</s><d>7.89234</d><enum>1</enum><int8>4</int8><uint16>5</uint16><int32>7</int32></Numbers>"
        let missingEnum = "<Numbers><b>true</b><i>45</i><s>3.4</s><d>7.89234</d></Numbers>"
        let wrongEnum = "<Strings><string>String1</string><optionalString>String2</optionalString><stringEnum>twenty</stringEnum></Strings>"
        let missingShape =
            "<Shape><Numbers><b>true</b><i>45</i><s>3.4</s><d>7.89234</d><enum>1</enum><int8>4</int8><uint16>5</uint16><int32>7</int32><uint64>90</uint64></Numbers><Strings><string>String1</string><optionalString>String2</optionalString><stringEnum>third</stringEnum></Strings></Shape>"
        let stringNotShape = "<Dictionaries><natives></natives><shapes><key>first</key><value>test</value></shapes></Dictionaries>"
        let notANumber = "<Dictionaries><natives><entry><key>first</key><value>test</value></entry></natives><shapes></shapes></Dictionaries>"

        do {
            var xmlDocument = try XML.Document(data: missingNative.data(using: .utf8)!)
            #expect(xmlDocument.rootElement() != nil)
            let result = try? XMLDecoder().decode(Numbers.self, from: xmlDocument.rootElement()!)
            #expect(result == nil)

            xmlDocument = try XML.Document(data: missingEnum.data(using: .utf8)!)
            #expect(xmlDocument.rootElement() != nil)
            let result2 = try? XMLDecoder().decode(Numbers.self, from: xmlDocument.rootElement()!)
            #expect(result2 == nil)

            xmlDocument = try XML.Document(data: wrongEnum.data(using: .utf8)!)
            #expect(xmlDocument.rootElement() != nil)
            let result3 = try? XMLDecoder().decode(StringShape.self, from: xmlDocument.rootElement()!)
            #expect(result3 == nil)

            xmlDocument = try XML.Document(data: missingShape.data(using: .utf8)!)
            #expect(xmlDocument.rootElement() != nil)
            let result4 = try? XMLDecoder().decode(Shape.self, from: xmlDocument.rootElement()!)
            #expect(result4 == nil)

            xmlDocument = try XML.Document(data: stringNotShape.data(using: .utf8)!)
            #expect(xmlDocument.rootElement() != nil)
            let result5 = try? XMLDecoder().decode(Dictionaries.self, from: xmlDocument.rootElement()!)
            #expect(result5 == nil)

            xmlDocument = try XML.Document(data: notANumber.data(using: .utf8)!)
            #expect(xmlDocument.rootElement() != nil)
            let result6 = try? XMLDecoder().decode(Dictionaries.self, from: xmlDocument.rootElement()!)
            #expect(result6 == nil)

        } catch {
            Issue.record(error)
        }
    }

    @Test func testDecodeExpandedContainers() {
        struct Shape: AWSDecodableShape {
            @CustomCoding<StandardArrayCoder> var array: [Int]
            @CustomCoding<StandardDictionaryCoder> var dictionary: [String: Int]
        }
        let xmldata =
            "<Shape><array><member>3</member><member>2</member><member>1</member></array><dictionary><entry><key>one</key><value>1</value></entry><entry><key>two</key><value>2</value></entry><entry><key>three</key><value>3</value></entry></dictionary></Shape>"
        if let shape = testDecode(type: Shape.self, xml: xmldata) {
            #expect(shape.array[0] == 3)
            #expect(shape.dictionary["two"] == 2)
        } else {
            Issue.record("Failed to decode")
        }
    }

    @Test func testArrayEncodingDecodeEncode() {
        struct Shape: AWSDecodableShape & AWSEncodableShape {
            @CustomCoding<StandardArrayCoder> var array: [Int]
        }
        let xmldata = "<Shape><array><member>3</member><member>2</member><member>1</member></array></Shape>"
        self.testDecodeEncode(type: Shape.self, xml: xmldata)
    }

    @Test func testArrayOfStructuresEncodingDecodeEncode() {
        struct Shape2: AWSDecodableShape & AWSEncodableShape {
            let value: String
        }
        struct Shape: AWSDecodableShape & AWSEncodableShape {
            @CustomCoding<StandardArrayCoder> var array: [Shape2]
        }
        let xmldata =
            "<Shape><array><member><value>test</value></member><member><value>test2</value></member><member><value>test3</value></member></array></Shape>"
        self.testDecodeEncode(type: Shape.self, xml: xmldata)
    }

    @Test func testDictionaryEncodingDecodeEncode() {
        struct DictionaryItemKeyValue: DictionaryCoderProperties {
            static let entry: String? = "item"
            static let key = "key"
            static let value = "value"
        }
        struct Shape: AWSDecodableShape & AWSEncodableShape {
            @CustomCoding<DictionaryCoder<DictionaryItemKeyValue, String, Int>> var d: [String: Int]
        }
        let xmldata = "<Shape><d><item><key>member</key><value>4</value></item></d></Shape>"
        self.testDecodeEncode(type: Shape.self, xml: xmldata)
    }

    @Test func testDictionaryOfStructuresEncodingDecodeEncode() {
        struct DictionaryItemKeyValue: DictionaryCoderProperties {
            static let entry: String? = "item"
            static let key = "key"
            static let value = "value"
        }
        struct Shape2: AWSDecodableShape & AWSEncodableShape {
            let float: Float
        }
        struct Shape: AWSDecodableShape & AWSEncodableShape {
            @CustomCoding<DictionaryCoder<DictionaryItemKeyValue, String, Shape2>> var d: [String: Shape2]
        }
        let xmldata = "<Shape><d><item><key>member</key><value><float>1.5</float></value></item></d></Shape>"
        self.testDecodeEncode(type: Shape.self, xml: xmldata)
    }

    @Test func testFlatDictionaryEncodingDecodeEncode() {
        struct DictionaryKeyValue: DictionaryCoderProperties {
            static let entry: String? = nil
            static let key = "key"
            static let value = "value"
        }
        struct Shape: AWSDecodableShape & AWSEncodableShape {
            @CustomCoding<DictionaryCoder<DictionaryKeyValue, String, Int>> var d: [String: Int]
        }
        let xmldata = "<Shape><d><key>member</key><value>4</value></d></Shape>"
        self.testDecodeEncode(type: Shape.self, xml: xmldata)
    }

    @Test func testEnumDictionaryEncodingDecodeEncode() {
        struct DictionaryItemKeyValue: DictionaryCoderProperties {
            static let entry: String? = "item"
            static let key = "key"
            static let value = "value"
        }
        enum KeyEnum: String, Codable {
            case member
            case member2
        }
        struct Shape: AWSDecodableShape & AWSEncodableShape {
            @CustomCoding<DictionaryCoder<DictionaryItemKeyValue, KeyEnum, Int>> var d: [KeyEnum: Int]
        }
        let xmldata = "<Shape><d><item><key>member</key><value>4</value></item></d></Shape>"
        self.testDecodeEncode(type: Shape.self, xml: xmldata)
    }

    @Test func testEnumShapeDictionaryEncodingDecodeEncode() {
        struct DictionaryItemKV: DictionaryCoderProperties {
            static let entry: String? = "item"
            static let key = "k"
            static let value = "v"
        }
        enum KeyEnum: String, Codable {
            case member
            case member2
        }
        struct Shape2: AWSDecodableShape & AWSEncodableShape {
            let a: String
        }
        struct Shape: AWSDecodableShape & AWSEncodableShape {
            @CustomCoding<DictionaryCoder<DictionaryItemKV, KeyEnum, Shape2>> var d: [KeyEnum: Shape2]
        }
        let xmldata = "<Shape><d><item><k>member</k><v><a>thisisastring</a></v></item></d></Shape>"
        self.testDecodeEncode(type: Shape.self, xml: xmldata)
    }

    @Test func testEnumFlatDictionaryEncodingDecodeEncode() {
        struct DictionaryKeyValue: DictionaryCoderProperties {
            static let entry: String? = nil
            static let key = "key"
            static let value = "value"
        }
        enum KeyEnum: String, Codable {
            case member
            case member2
        }
        struct Shape2: AWSDecodableShape & AWSEncodableShape {
            let a: String
        }
        struct Shape: AWSDecodableShape & AWSEncodableShape {
            @CustomCoding<DictionaryCoder<DictionaryKeyValue, KeyEnum, Shape2>> var d: [KeyEnum: Shape2]
        }
        let xmldata = "<Shape><d><key>member</key><value><a>hello</a></value></d></Shape>"
        self.testDecodeEncode(type: Shape.self, xml: xmldata)
    }

    @Test func testEncodeDecodeXML() {
        do {
            if let xml = try XMLEncoder().encode(self.testShape) {
                let testShape2 = try XMLDecoder().decode(Shape.self, from: xml)
                let xml2 = try XMLEncoder().encode(testShape2)

                #expect(xml.xmlString == xml2?.xmlString)
            } else {
                Issue.record("Failed to create any XML")
            }
        } catch {
            Issue.record(error)
        }
    }

    @Test func testEncodeDecodeDictionariesXML() {
        do {
            if let xml = try XMLEncoder().encode(self.testShapeWithDictionaries) {
                let testShape2 = try XMLDecoder().decode(ShapeWithDictionaries.self, from: xml)

                #expect(testShape2.dictionaries.dictionaryOfNatives["second"] == 2)
                #expect(testShape2.dictionaries.dictionaryOfShapes["strings2"]?.stringEnum == .fourth)
            } else {
                Issue.record("Failed to create any XML")
            }
        } catch {
            Issue.record(error)
        }
    }

    @Test func testSingleValueContainer() {
        struct Test2: Codable {
            var a: [String]
        }
        struct Test: Codable {
            var t: Test2?

            init(from decoder: Decoder) throws {
                let container = try decoder.singleValueContainer()
                self.t = try container.decode(Test2.self)
            }

            func encode(to encoder: Encoder) throws {
                var container = encoder.singleValueContainer()
                try container.encode(self.t)
            }
        }
        let xml = "<Test><a>one</a></Test>"
        self.testDecodeEncode(type: Test.self, xml: xml)
    }

    @Test func testSingleValueContainerEncode() throws {
        struct Test2: Encodable {
            var a: [String]
        }
        struct Test: Encodable {
            var t: Test2?

            func encode(to encoder: Encoder) throws {
                var container = encoder.singleValueContainer()
                try container.encode(self.t)
            }
        }
        let xml = try XMLEncoder().encode(Test(t: nil))
        #expect(xml == nil)
    }
}
