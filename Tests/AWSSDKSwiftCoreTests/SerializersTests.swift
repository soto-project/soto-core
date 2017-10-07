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
    
    struct A: AWSShape {
        public static var members: [AWSShapeMember] = [
            AWSShapeMember(label: "structure", required: true, type: .structure),
            AWSShapeMember(label: "structures", required: false, type: .list),
            AWSShapeMember(label: "array", required: true, type: .list)
        ]
        
        let structure = B()
        let dList: [D] = [D()]
        let cList: [C] = [C()]
        let array: [String] = ["foo", "bar"]
    }
    
    func testSerializeToXML() {
        let node = try! AWSShapeEncoder().encodeToXMLNode(A(), attributes: ["A": ["url": "https://example.com"]])
        XCTAssertEqual(node.attributes["url"], "https://example.com")
        
        let xml = XMLNodeSerializer(node: node).serializeToXML()
        let expected = "<A url=\"https://example.com\"><Structure><A>1</A><B>1</B><B>2</B><C><key>value</key></C></Structure><DList><Value>world</Value></DList><CList><Value>hello</Value></CList><Array>foo</Array><Array>bar</Array></A>"
        XCTAssertEqual(xml, expected)
    }
    
    func testSerializeToDictionaryAndJSON() {
        let node = try! AWSShapeEncoder().encodeToXMLNode(A())
        let json = XMLNodeSerializer(node: node).serializeToJSON()
        let dict = try! JSONSerializer().serializeToDictionary(json.data)
        let jsonObect = try! JSONSerialization.jsonObject(with: json.data, options: []) as! [String: Any]
        XCTAssertEqual(dict.count, jsonObect.count)
    }
    
    func testSerializeToFlatDictionary() {
        let data = try! JSONEncoder().encode(A())
        let dict = try! JSONSerializer().serializeToFlatDictionary(data)

        XCTAssertEqual(dict.count, 8)
        XCTAssertEqual(dict["structure.a"] as? String, "1")
        XCTAssertEqual(dict["structure.c.key"] as? String, "value")
        XCTAssertEqual(dict["array.member.1"] as? String, "foo")
        XCTAssertEqual(dict["array.member.2"] as? String, "bar")
    }
    
    static var allTests : [(String, (SerializersTests) -> () throws -> Void)] {
        return [
            ("testSerializeToXML", testSerializeToXML),
            ("testSerializeToDictionaryAndJSON", testSerializeToDictionaryAndJSON),
            ("testSerializeToFlatDictionary", testSerializeToFlatDictionary)
        ]
    }
}
