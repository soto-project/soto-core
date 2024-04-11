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

import struct Foundation.Data

/// Implemented to replace the XML Foundation classes. This was initially required as there is no implementation of the Foundation XMLNode classes in iOS. This is also here because the implementation of XMLNode in Linux Swift 4.2 was causing crashes. Whenever an XMLDocument was deleted all the underlying CoreFoundation objects were deleted. This meant if you still had a reference to a XMLElement from that document, while it was still valid the underlying CoreFoundation object had been deleted.
///
/// I have placed everything inside a holding XML enumeration to avoid name clashes with the Foundation version. Otherwise this class reflects the behaviour of the Foundation classes as close as possible with the exceptions of, I haven't implemented queries, DTD, also XMLNodes do not contain an object reference. Also the node creation function in XMLNode return XMLNode instead of Any.
public enum XML {
    /// base class for all types of XML.Node
    public class Node {
        /// XML node type
        public enum Kind {
            case document
            case element
            case text
            case attribute
            case namespace
            case comment
        }

        /// defines the type of xml node
        public let kind: Kind
        public var name: String?
        public var stringValue: String?
        public fileprivate(set) var children: [XML.Node]?
        public weak var parent: XML.Node?

        fileprivate init(_ kind: Kind, name: String? = nil, stringValue: String? = nil) {
            self.kind = kind
            self.name = name
            self.stringValue = stringValue
            self.children = nil
            self.parent = nil
        }

        /// create XML document node
        public static func document() -> XML.Node {
            return XML.Document()
        }

        /// create XML element node
        public static func element(withName: String, stringValue: String? = nil) -> XML.Node {
            return XML.Element(name: withName, stringValue: stringValue)
        }

        /// create raw text node
        public static func text(stringValue: String) -> XML.Node {
            return XML.Node(.text, stringValue: stringValue)
        }

        /// create XML attribute node
        public static func attribute(withName: String, stringValue: String) -> XML.Node {
            return XML.Node(.attribute, name: withName, stringValue: stringValue)
        }

        /// create XML namespace node
        public static func namespace(withName: String? = nil, stringValue: String) -> XML.Node {
            return XML.Node(.namespace, name: withName, stringValue: stringValue)
        }

        /// create XML comment node
        public static func comment(stringValue: String) -> XML.Node {
            return XML.Node(.comment, stringValue: stringValue)
        }

        /// return child node at index
        private func child(at index: Int) -> XML.Node? {
            return self.children?[index]
        }

        /// return number of children
        public var childCount: Int { return self.children?.count ?? 0 }

        /// detach XML node from its parent
        public func detach() {
            self.parent?.detach(child: self)
            self.parent = nil
        }

        /// detach child XML Node
        fileprivate func detach(child: XML.Node) {
            self.children?.removeAll(where: { $0 === child })
        }

        /// return children of a specific kind
        public func children(of kind: Kind) -> [XML.Node]? {
            return self.children?.compactMap { $0.kind == kind ? $0 : nil }
        }

        private static let xmlEncodedCharacters: [String.Element: String] = [
            "&": "&amp;",
            "<": "&lt;",
            ">": "&gt;",
        ]
        /// encode text with XML markup
        private static func xmlEncode(string: String) -> String {
            var newString = ""
            for c in string {
                if let replacement = XML.Node.xmlEncodedCharacters[c] {
                    newString.append(contentsOf: replacement)
                } else {
                    newString.append(c)
                }
            }
            return newString
        }

        /// output formatted XML
        public var xmlString: String {
            switch self.kind {
            case .text:
                if let stringValue {
                    return XML.Node.xmlEncode(string: stringValue)
                }
                return ""
            case .attribute:
                if let name {
                    return "\(name)=\"\(self.stringValue ?? "")\""
                } else {
                    return ""
                }
            case .comment:
                if let stringValue {
                    return "<!--\(stringValue)-->"
                } else {
                    return ""
                }
            case .namespace:
                var string = "xmlns"
                if let name, name != "" {
                    string += ":\(name)"
                }
                string += "=\"\(self.stringValue ?? "")\""
                return string
            default:
                return ""
            }
        }
    }

    /// XML Document class
    public final class Document: XML.Node {
        public var version: String?
        public var characterEncoding: String?

        public init() {
            super.init(.document)
        }

        public init(rootElement: XML.Element) {
            super.init(.document)
            self.setRootElement(rootElement)
        }

        /// initialise with a block XML data
        public init(data: Data) throws {
            super.init(.document)
            do {
                let element = try XML.Element(xmlData: data)
                self.setRootElement(element)
            } catch ParsingError.emptyFile {}
        }

        /// initialise XML.Document from xml string
        public init(string: String) throws {
            super.init(.document)
            do {
                let element = try XML.Element(xmlString: string)
                self.setRootElement(element)
            } catch ParsingError.emptyFile {}
        }

        /// set the root element of the document
        public func setRootElement(_ rootElement: XML.Element) {
            for child in self.children ?? [] {
                child.parent = nil
            }
            children = [rootElement]
        }

        /// return the root element
        public func rootElement() -> XML.Element? {
            return children?.first { return ($0 as? XML.Element) != nil } as? XML.Element
        }

        /// output formatted XML
        override public var xmlString: String {
            var string = "<?xml version=\"\(version ?? "1.0")\" encoding=\"\(characterEncoding ?? "UTF-8")\"?>"
            if let rootElement = rootElement() {
                string += rootElement.xmlString
            }
            return string
        }

        /// output formatted XML as Data
        public var xmlData: Data { return self.xmlString.data(using: .utf8) ?? Data() }
    }

    /// XML Element class
    public final class Element: XML.Node {
        /// array of attributes attached to XML ELement
        public fileprivate(set) var attributes: [XML.Node]?
        /// array of namespaces attached to XML ELement
        public fileprivate(set) var namespaces: [XML.Node]?

        public init(name: String, stringValue: String? = nil) {
            super.init(.element, name: name)
            self.stringValue = stringValue
        }

        /// initialise XML.Element from xml string
        public init(xmlString: String) throws {
            super.init(.element)

            if let rootElement = try Self.parse(xml: xmlString) {
                // copy contents of rootElement
                self.setChildren(rootElement.children)
                self.setAttributes(rootElement.attributes)
                self.setNamespaces(rootElement.namespaces)
                self.name = rootElement.name
            } else {
                throw ParsingError.emptyFile
            }
        }

        /// initialise XML.Element from xml data
        public convenience init(xmlData: Data) throws {
            let xml = String(decoding: xmlData, as: Unicode.UTF8.self)
            try self.init(xmlString: xml)
        }

        /// Parse XML string and return an XML root element
        static func parse(xml: String) throws -> Element? {
            var rootElement: XML.Element?
            var currentElement: XML.Element?
            var currentNamespace: XML.Node?

            let parser = try Expat()
                .onStartElement { name, attrs in
                    let element = XML.Element(name: name)
                    for attribute in attrs {
                        element.addAttribute(XML.Node(.attribute, name: attribute.key, stringValue: attribute.value))
                    }
                    if rootElement == nil {
                        rootElement = element
                    }
                    currentElement?.addChild(element)
                    currentElement = element
                    if let namespace = currentNamespace {
                        currentElement?.addNamespace(namespace)
                        currentNamespace = nil
                    }
                }
                .onEndElement { name in
                    assert(currentElement?.name == name)
                    currentElement = currentElement?.parent as? XML.Element
                }
                .onCharacterData { characters in
                    // if string with white space removed still has characters, add text node
                    if characters.split(omittingEmptySubsequences: true, whereSeparator: { $0.isWhitespace && !$0.isNewline }).joined().count > 0 {
                        currentElement?.addChild(XML.Node.text(stringValue: characters))
                    }
                }
                .onComment { comment in
                    currentElement?.addChild(.comment(stringValue: comment))
                }

            _ = try parser.feed(xml)
            _ = try parser.close()

            return rootElement
        }

        /// return children XML elements
        public func elements(forName: String) -> [XML.Element] {
            return children?.compactMap {
                if let element = $0 as? XML.Element, element.name == forName {
                    return element
                }
                return nil
            } ?? []
        }

        /// return child text nodes all concatenated together
        override public var stringValue: String? {
            get {
                let textNodes = children(of: .text)
                let text = textNodes?.reduce("") { return $0 + ($1.stringValue ?? "") } ?? ""
                return text
            }
            set(value) {
                children?.removeAll { $0.kind == .text }
                if let value {
                    self.addChild(XML.Node(.text, stringValue: value))
                }
            }
        }

        /// add a child node to the xml element
        public func addChild(_ node: XML.Node) {
            assert(node.kind != .namespace && node.kind != .attribute && node.kind != .document)
            assert(node !== self)
            if children == nil {
                children = [node]
            } else {
                children!.append(node)
            }
            node.parent = self
        }

        /// insert a child node at position in the list of children nodes
        public func insertChild(node: XML.Node, at index: Int) {
            assert(node.kind != .namespace && node.kind != .attribute && node.kind != .document)
            children?.insert(node, at: index)
            node.parent = self
        }

        /// set this elements children nodes
        public func setChildren(_ children: [XML.Node]?) {
            for child in self.children ?? [] {
                child.parent = nil
            }
            self.children = children
            for child in self.children ?? [] {
                assert(child.kind != .namespace && child.kind != .attribute && child.kind != .document)
                child.parent = self
            }
        }

        /// return attribute attached to element
        public func attribute(forName: String) -> XML.Node? {
            return self.attributes?.first {
                if $0.name == forName {
                    return true
                }
                return false
            }
        }

        /// add an attribute to an element. If one with this name already exists it is replaced
        public func addAttribute(_ node: XML.Node) {
            assert(node.kind == .attribute)
            if let name = node.name, let attributeNode = attribute(forName: name) {
                attributeNode.detach()
            }
            if self.attributes == nil {
                self.attributes = [node]
            } else {
                self.attributes!.append(node)
            }
            node.parent = self
        }

        /// set this elements children nodes
        public func setAttributes(_ attributes: [XML.Node]?) {
            for attribute in self.attributes ?? [] {
                attribute.parent = nil
            }
            self.attributes = attributes
            for attribute in self.attributes ?? [] {
                assert(attribute.kind == .attribute)
                attribute.parent = self
            }
        }

        /// return namespace attached to element
        public func namespace(forName: String?) -> XML.Node? {
            return self.namespaces?.first {
                if $0.name == forName {
                    return true
                }
                return false
            }
        }

        /// add a namespace to an element. If one with this name already exists it is replaced
        public func addNamespace(_ node: XML.Node) {
            assert(node.kind == .namespace)
            if let attributeNode = namespace(forName: node.name) {
                attributeNode.detach()
            }
            if self.namespaces == nil {
                self.namespaces = [node]
            } else {
                self.namespaces!.append(node)
            }
            node.parent = self
        }

        /// set this elements children nodes
        public func setNamespaces(_ namespaces: [XML.Node]?) {
            for namespace in self.namespaces ?? [] {
                namespace.parent = nil
            }
            self.namespaces = namespaces
            for namespace in self.namespaces ?? [] {
                assert(namespace.kind == .namespace)
                namespace.parent = self
            }
        }

        /// detach child XML Node
        override fileprivate func detach(child: XML.Node) {
            switch child.kind {
            case .attribute:
                self.attributes?.removeAll(where: { $0 === child })
            case .namespace:
                self.namespaces?.removeAll(where: { $0 === child })
            default:
                super.detach(child: child)
            }
        }

        /// return formatted XML
        override public var xmlString: String {
            var string = ""
            string += "<\(name!)"
            string += self.namespaces?.map { " " + $0.xmlString }.joined(separator: "") ?? ""
            string += self.attributes?.map { " " + $0.xmlString }.joined(separator: "") ?? ""
            string += ">"
            for node in children ?? [] {
                string += node.xmlString
            }
            string += "</\(name!)>"
            return string
        }
    }

    /// XML parsing errors
    enum ParsingError: Error {
        case emptyFile
        case noXMLFound
        case parseError

        var localizedDescription: String {
            switch self {
            case .emptyFile:
                return "File contained nothing"
            case .parseError:
                return "Error parsing file"
            case .noXMLFound:
                return "File didn't contain any XML"
            }
        }
    }
}

extension XML.Node: CustomStringConvertible, CustomDebugStringConvertible {
    /// CustomStringConvertible protocol
    public var description: String { return xmlString }
    /// CustomDebugStringConvertible protocol
    public var debugDescription: String { return xmlString }
}

extension Character {
    var isWhitespaceOrNewline: Bool { return isWhitespace || isNewline }
}
