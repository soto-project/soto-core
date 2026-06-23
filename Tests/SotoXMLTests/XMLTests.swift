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

@testable import SotoXML

class XMLTests {
    /// helper test function to use throughout all the decode/encode tests
    func testDecodeEncode(xml: String) throws {
        var xmlDocument: XML.Document?
        #expect(throws: Never.self) { xmlDocument = try XML.Document(data: Data(xml.utf8)) }
        let xml2 = xmlDocument?.xmlString
        #expect(xml == xml2)
    }

    @Test func testAddChild() {
        let element = XML.Element(name: "test")
        let element2 = XML.Element(name: "test2")
        element.addChild(element2)
        element2.addChild(XML.Node.text(stringValue: "TestString"))
        #expect(element.xmlString == "<test><test2>TestString</test2></test>")
    }

    @Test func testAddRemoveChild() {
        let element = XML.Element(name: "test")
        let element2 = XML.Element(name: "test2")
        element.addChild(element2)
        element2.addChild(XML.Node.text(stringValue: "TestString"))
        element2.detach()
        #expect(element.xmlString == "<test></test>")
    }

    @Test func testAttributeAdd() {
        let element = XML.Element(name: "test", stringValue: "data")
        element.addAttribute(XML.Node.attribute(withName: "attribute", stringValue: "value"))
        #expect(element.xmlString == "<test attribute=\"value\">data</test>")
    }

    @Test func testAttributeReplace() {
        let element = XML.Element(name: "test", stringValue: "data")
        element.addAttribute(XML.Node.attribute(withName: "attribute", stringValue: "value"))
        element.addAttribute(XML.Node.attribute(withName: "attribute", stringValue: "value2"))
        #expect(element.xmlString == "<test attribute=\"value2\">data</test>")
    }

    @Test func testNamespaceAdd() {
        let element = XML.Element(name: "test", stringValue: "data")
        element.addNamespace(XML.Node.namespace(withName: "name", stringValue: "http://me.com/"))
        #expect(element.xmlString == "<test xmlns:name=\"http://me.com/\">data</test>")
    }

    @Test func testNamespaceReplace() {
        let element = XML.Element(name: "test", stringValue: "data")
        element.addNamespace(XML.Node.namespace(withName: "name", stringValue: "http://me.com/"))
        element.addNamespace(XML.Node.namespace(withName: "name", stringValue: "http://me2.com/"))
        #expect(element.xmlString == "<test xmlns:name=\"http://me2.com/\">data</test>")
    }

    @Test func testNullNamespaceReplace() {
        let element = XML.Element(name: "test", stringValue: "data")
        element.addNamespace(XML.Node.namespace(stringValue: "http://me.com/"))
        element.addNamespace(XML.Node.namespace(stringValue: "http://me2.com/"))
        #expect(element.xmlString == "<test xmlns=\"http://me2.com/\">data</test>")
    }

    @Test func testDocumentDefaultOutput() {
        let document = XML.Node.document()
        #expect(document.xmlString == "<?xml version=\"1.0\" encoding=\"UTF-8\"?>")
    }

    @Test func testAttributesDecodeEncode() {
        let xml = "<?xml version=\"1.0\" encoding=\"UTF-8\"?><test name=\"test\">testing</test>"
        #expect(throws: Never.self) { try self.testDecodeEncode(xml: xml) }
    }

    @Test func testNamespacesDecodeEncode() {
        let xml = "<?xml version=\"1.0\" encoding=\"UTF-8\"?><test xmlns=\"http://www.w3.org/TR/html4/\">testing<a>child</a></test>"
        #expect(throws: Never.self) { try self.testDecodeEncode(xml: xml) }
        let xml2 = "<?xml version=\"1.0\" encoding=\"UTF-8\"?><test xmlns:h=\"http://www.w3.org/TR/html4/\">testing<a>child</a></test>"
        #expect(throws: Never.self) { try self.testDecodeEncode(xml: xml2) }
    }

    @Test func testArrayDecodeEncode() {
        let xml = "<?xml version=\"1.0\" encoding=\"UTF-8\"?><array><test>testing1</test><test>testing2</test><test>testing3</test></array>"
        #expect(throws: Never.self) { try self.testDecodeEncode(xml: xml) }
    }

    @Test func testCommentDecodeEncode() {
        let xml = "<?xml version=\"1.0\" encoding=\"UTF-8\"?><test>testing<!--Test Comment--></test>"
        #expect(throws: Never.self) { try self.testDecodeEncode(xml: xml) }
    }

    @Test func testCDATADecodeEncode() {
        let xml = "<?xml version=\"1.0\" encoding=\"UTF-8\"?><test><![CDATA[CDATA test]]></test>"
        var xmlDocument: XML.Document?
        #expect(throws: Never.self) { xmlDocument = try XML.Document(data: Data(xml.utf8)) }
        let xml2 = xmlDocument?.xmlString
        #expect(xml2 == "<?xml version=\"1.0\" encoding=\"UTF-8\"?><test>CDATA test</test>")
    }

    @Test func testWhitespaceDecodeEncode() {
        let xml = "<?xml version=\"1.0\" encoding=\"UTF-8\"?><test> <a> before</a><b></b> <c>after </c></test>"
        var xmlDocument: XML.Document?
        #expect(throws: Never.self) { xmlDocument = try XML.Document(data: Data(xml.utf8)) }
        let xml2 = xmlDocument?.xmlString
        #expect(xml2 == "<?xml version=\"1.0\" encoding=\"UTF-8\"?><test><a> before</a><b></b><c>after </c></test>")
    }

    @Test func testNewlines() {
        let xml = """
            <?xml version=\"1.0\" encoding=\"UTF-8\"?><test>Hello

            Goodbye</test>
            """
        #expect(throws: Never.self) { try self.testDecodeEncode(xml: xml) }
    }

    @Test func testDecodeRubbish() {
        let xml = "{}"
        #expect(throws: XMLError.self) { try XML.Document(data: Data(xml.utf8)) }
    }
}
