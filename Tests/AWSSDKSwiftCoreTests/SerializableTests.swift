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

typealias Serializable = DictionarySerializable & XMLNodeSerializable

class SerializableTests: XCTestCase {
    
    struct B: Serializable {
        public static var parsingHints: [AWSShapeProperty] = [
            AWSShapeProperty(label: "a", required: true, type: .string),
            AWSShapeProperty(label: "b", required: false, type: .list),
            AWSShapeProperty(label: "c", required: true, type: .list)
        ]
        
        let a = "1"
        let b = [1, 2]
        let c = ["key": "value"]
    }
    
    struct C: Serializable {
        public static var parsingHints: [AWSShapeProperty] = [
            AWSShapeProperty(label: "value", required: true, type: .string)
        ]
        
        let value = "hello"
    }
    
    struct D: Serializable {
        public static var parsingHints: [AWSShapeProperty] = [
            AWSShapeProperty(label: "value", required: true, type: .string)
        ]
        
        let value = "world"
    }
    
    struct A: Serializable {
        public static var parsingHints: [AWSShapeProperty] = [
            AWSShapeProperty(label: "structure", required: true, type: .structure),
            AWSShapeProperty(label: "structures", required: false, type: .list),
            AWSShapeProperty(label: "array", required: true, type: .list)
        ]
        
        let structure = B()
        let structures: [Serializable] = [C(), D()]
        let array = ["foo", "bar"]
    }
    
    static var allTests : [(String, (SerializableTests) -> () throws -> Void)] {
        return [
            ("testSerializeToXML", testSerializeToXML),
            ("testSerializeToDictionaryAndJSON", testSerializeToDictionaryAndJSON),
            ("testSerializeToFlatDictionary", testSerializeToFlatDictionary)
        ]
    }
    
    func testSerializeToXML() {
        let node = try! A().serializeToXMLNode(attributes: ["A": ["url": "https://example.com"]])
        XCTAssertEqual(node.attributes["url"], "https://example.com")
        
        let xml = XMLNodeSerializer(node: node).serializeToXML()
        let expected = "<A url=\"https://example.com\"><Structure><A>1</A><B>1</B><B>2</B><C><key>value</key></C></Structure><Structures><Value>hello</Value><Value>world</Value></Structures><Array>foo</Array><Array>bar</Array></A>"
        XCTAssertEqual(xml, expected)
    }
    
    func testSerializeToDictionaryAndJSON() {
        let dict = try! A().serializeToDictionary()
        let data = try! JSONSerializer.serialize(dict)
        let jsonObect = try! JSONSerialization.jsonObject(with: data, options: []) as! [String: Any]
        XCTAssertEqual(dict.count, jsonObect.count)
    }
    
    func testSerializeToFlatDictionary() {
        let dict = try! A().serializeToFlatDictionary()
        XCTAssertEqual(dict.count, 8)
        XCTAssertEqual(dict["structure.a"] as? String, "1")
        XCTAssertEqual(dict["structure.c.key"] as? String, "value")
        XCTAssertEqual(dict["array.member.1"] as? String, "foo")
        XCTAssertEqual(dict["array.member.2"] as? String, "bar")
    }
    
}
