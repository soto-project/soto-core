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

    struct B: AWSShape {
        public static var members: [AWSShapeMember] = [
            AWSShapeMember(label: "a", required: true, type: .string),
            AWSShapeMember(label: "b", required: false, type: .list),
            AWSShapeMember(label: "c", required: true, type: .list)
        ]

        let a = "1"
        let b = [1, 2]
        let c = ["key": "value"]
    }

    struct C: AWSShape {
        public static var members: [AWSShapeMember] = [
            AWSShapeMember(label: "value", required: true, type: .string)
        ]

        let value = "hello"
    }

    struct D: AWSShape {
        public static var members: [AWSShapeMember] = [
            AWSShapeMember(label: "value", required: true, type: .string)
        ]

        let value = "world"
    }

    struct E: AWSShape {
      public static var members: [AWSShapeMember] = [
          AWSShapeMember(label: "Member", required: true, type: .list),
      ]

      let Member = ["memberKey": "memberValue", "memberKey2": "memberValue2"]
    }

    struct A: AWSShape {
        public static var members: [AWSShapeMember] = [
            AWSShapeMember(label: "structure", required: true, type: .structure),
            AWSShapeMember(label: "structures", required: false, type: .list),
            AWSShapeMember(label: "array", required: true, type: .list),
            AWSShapeMember(label: "member", required: true, type: .list)
        ]

        let structure = B()
        let dList: [D] = [D()]
        let cList: [C] = [C()]
        let array: [String] = ["foo", "bar"]
        let structureWithMember = E()
        let structureWithMembers: [E] = [E(), E()]
    }

    func testSerializeToXML() {
        let node = try! AWSShapeEncoder().encodeToXMLNode(A(), attributes: ["A": ["url": "https://example.com"]])
        XCTAssertEqual(node.attributes["url"], "https://example.com")

        let xml = XMLNodeSerializer(node: node).serializeToXML()

        let valid1 = "<A url=\"https://example.com\"><Structure><A>1</A><B>1</B><B>2</B><C><key>value</key></C></Structure><DList><Value>world</Value></DList><CList><Value>hello</Value></CList><Array>foo</Array><Array>bar</Array><StructureWithMember><Member><memberKey2>memberValue2</memberKey2><memberKey>memberValue</memberKey></Member></StructureWithMember><StructureWithMembers><Member><memberKey2>memberValue2</memberKey2><memberKey>memberValue</memberKey></Member><Member><memberKey2>memberValue2</memberKey2><memberKey>memberValue</memberKey></Member></StructureWithMembers></A>"

        // order of the StructureWithMember dictionary does not matter
        let valid2 = "<A url=\"https://example.com\"><Structure><A>1</A><B>1</B><B>2</B><C><key>value</key></C></Structure><DList><Value>world</Value></DList><CList><Value>hello</Value></CList><Array>foo</Array><Array>bar</Array><StructureWithMember><Member><memberKey>memberValue</memberKey><memberKey2>memberValue2</memberKey2></Member></StructureWithMember><StructureWithMembers><Member><memberKey>memberValue</memberKey><memberKey2>memberValue2</memberKey2></Member><Member><memberKey>memberValue</memberKey><memberKey2>memberValue2</memberKey2></Member></StructureWithMembers></A>"

        let validSerialized = [valid1,valid2]

        XCTAssert(validSerialized.contains(xml))
    }

    func testSerializeToDictionaryAndJSON() {
        let node = try! AWSShapeEncoder().encodeToXMLNode(A())
        let json = XMLNodeSerializer(node: node).serializeToJSON()
        let json_data = json.data(using: .utf8)!
        let dict = try! JSONSerializer().serializeToDictionary(json_data)
        let jsonObect = try! JSONSerialization.jsonObject(with: json_data, options: []) as! [String: Any]
        XCTAssertEqual(dict.count, jsonObect.count)

        // Member scalar
        let fromDict = dict["A"]! as! [String: Any]
        let swmFromDict = fromDict["StructureWithMember"] as! [String: String]
        XCTAssertEqual(swmFromDict["memberKey"], "memberValue")

        let fromJson = jsonObect["A"]! as! [String: Any]
        let swmFromJson = fromJson["StructureWithMember"] as! [String: String]
        XCTAssertEqual(swmFromJson["memberKey"], "memberValue")

        // Member list
        let swmsFromDict = fromDict["StructureWithMembers"] as! [Any]
        let swmFirstFromDict = swmsFromDict.first! as! [String: String]
        XCTAssertEqual(swmFirstFromDict["memberKey"], "memberValue")

        let swmSecondFromDict = swmsFromDict.last! as! [String: String]
        XCTAssertEqual(swmSecondFromDict["memberKey2"], "memberValue2")

        let swmsFromJson = fromJson["StructureWithMembers"] as! [Any]
        let swmFirstFromJson = swmsFromJson.first! as! [String: String]
        XCTAssertEqual(swmFirstFromJson["memberKey"], "memberValue")

        let swmSecondFromJson = swmsFromJson.last! as! [String: String]
        XCTAssertEqual(swmSecondFromJson["memberKey2"], "memberValue2")
    }

    func testLowercasedBoolean() {
        let node = try! XML2Parser(data: "<A>True</A>".data(using: .utf8)!).parse()
        let str = XMLNodeSerializer(node: node).serializeToJSON()
        XCTAssertEqual(str, "{\"A\":true}")

        let outputDict = try! JSONSerialization.jsonObject(with: str.data(using: .utf8)!, options: []) as? [String: Any] ?? [:]
        XCTAssertEqual(outputDict["A"] as? Bool, true)
        XCTAssertEqual(outputDict.count, 1)
    }

    func testSerializeToFlatDictionary() {
        let data = try! JSONEncoder().encode(A())
        let dict = try! JSONSerializer().serializeToFlatDictionary(data)

        XCTAssertEqual(dict.count, 12)
        XCTAssertEqual(dict["structure.a"] as? String, "1")
        XCTAssertEqual(dict["structure.c.key"] as? String, "value")
        XCTAssertEqual(dict["array.member.1"] as? String, "foo")
        XCTAssertEqual(dict["array.member.2"] as? String, "bar")
    }

    static var allTests : [(String, (SerializersTests) -> () throws -> Void)] {
        return [
            ("testSerializeToXML", testSerializeToXML),
            ("testSerializeToDictionaryAndJSON", testSerializeToDictionaryAndJSON),
            ("testLowercasedBoolean", testLowercasedBoolean),
            ("testSerializeToFlatDictionary", testSerializeToFlatDictionary)
        ]
    }
}
