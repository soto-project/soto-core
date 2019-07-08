//
//  XML.swift
//  AWSSDKSwift
//
//  Created by Adam Fowler on 2019/06/15
//
//
import Foundation

public class XML {
    /// base class for all types of XML.Node
    public class Node : CustomStringConvertible, CustomDebugStringConvertible {
        
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
        public let kind : Kind
        public var name : String?
        public var stringValue : String?
        public fileprivate(set) var children : [XML.Node]?
        public weak var parent : XML.Node?
        
        init(kind: Kind) {
            self.kind = kind
            self.children = nil
            self.parent = nil
        }
        
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
            return children?[index]
        }
        
        /// return number of children
        public var childCount : Int { get {return children?.count ?? 0}}
        
        /// detach XML node from its parent
        public func detach() {
            parent?.detach(child:self)
            parent = nil
        }
        
        /// detach child XML Node
        fileprivate func detach(child: XML.Node) {
            children?.removeAll(where: {$0 === child})
        }
        
        /// return children of a specific kind
        func children(of kind: Kind) -> [XML.Node]? {
            return children?.compactMap { $0.kind == kind ? $0 : nil }
        }
        
        private static let xmlEncodedCharacters : [String.Element: String] = [
            "\"": "&quot;",
            "&": "&amp;",
            "'": "&apos;",
            "<": "&lt;",
            ">": "&gt;",
        ]
        /// encode text with XML markup
        private static func xmlEncode(string: String) -> String {
            var newString = ""
            for c in string {
                if let replacement = XML.Node.xmlEncodedCharacters[c] {
                    newString.append(contentsOf:replacement)
                } else {
                    newString.append(c)
                }
            }
            return newString
        }
        
        /// output formatted XML
        public var xmlString : String {
            switch kind {
            case .text:
                if let stringValue = stringValue {
                    return XML.Node.xmlEncode(string: stringValue)
                }
                return ""
            case .attribute:
                if let name = name {
                    return "\(name)=\"\(stringValue ?? "")\""
                } else {
                    return ""
                }
            case .comment:
                if let stringValue = stringValue {
                    return "<!--\(stringValue)-->"
                } else {
                    return ""
                }
            case .namespace:
                var string = "xmlns"
                if let name = name, name != "" {
                    string += ":\(name)"
                }
                string += "=\"\(stringValue ?? "")\""
                return string
            default:
                return ""
            }
        }
        
        /// CustomStringConvertible protocol
        public var description: String {return xmlString}
        /// CustomDebugStringConvertible protocol
        public var debugDescription: String {return xmlString}
    }
    
    /// XML Document class
    public class Document : XML.Node {
        public var version : String?
        public var characterEncoding : String?
        
        public init() {
            super.init(.document)
        }
        
        public init(rootElement: XML.Element) {
            super.init(.document)
            setRootElement(rootElement)
        }
        
        /// initialise with a block XML data
        public init(data: Data) throws {
            super.init(.document)
            do {
                let element = try XML.Element(xmlData: data)
                setRootElement(element)
            } catch ParsingError.emptyFile {
            }
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
            return children?.first {return ($0 as? XML.Element) != nil} as? XML.Element
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
        public var xmlData : Data { return xmlString.data(using: .utf8) ?? Data()}
        
    }
    
    /// XML Element class
    public class Element : XML.Node {
        
        /// array of attributes attached to XML ELement
        public fileprivate(set) var attributes : [XML.Node]?
        /// array of namespaces attached to XML ELement
        public fileprivate(set) var namespaces : [XML.Node]?

        public init(name: String, stringValue: String? = nil) {
            super.init(.element, name: name)
            self.stringValue = stringValue
        }
        
        /// initialise XML.Element from xml data
        public init(xmlData: Data) throws {
            super.init(.element)
            let parser = XMLParser(data: xmlData)
            let parserDelegate = ParserDelegate()
            parser.delegate = parserDelegate
            if !parser.parse() {
                if let error = parserDelegate.error {
                    throw error
                }
            } else if let rootElement = parserDelegate.rootElement {
                self.setChildren(rootElement.children)
                self.setAttributes(rootElement.attributes)
                self.setNamespaces(rootElement.namespaces)
                self.name = rootElement.name
            } else {
                throw ParsingError.emptyFile
            }
        }
        
        /// initialise XML.Element from xml string
        convenience public init(xmlString: String) throws {
            let data = xmlString.data(using: .utf8)!
            try self.init(xmlData: data)
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
        public override var stringValue : String? {
            get {
                let textNodes = children(of:.text)
                let text = textNodes?.reduce("", { return $0 + ($1.stringValue ?? "")}) ?? ""
                return text
            }
            set(value) {
                children?.removeAll {$0.kind == .text}
                if let value = value {
                    addChild(XML.Node(.text, stringValue: value))
                }
            }
        }
        
        /// add a child node to the xml element
        public func addChild(_ node: XML.Node) {
            assert(node.kind != .namespace && node.kind != .attribute && node.kind != .document)
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
                child.parent = self
            }
        }
        
        /// return attribute attached to element
        public func attribute(forName: String) -> XML.Node? {
            return attributes?.first {
                if $0.name == forName {
                    return true
                }
                return false
            }
        }
        
        /// add an attribute to an element. If one with this name already exists it is replaced
        public func addAttribute(_ node : XML.Node) {
            if let name = node.name, let attributeNode = attribute(forName: name) {
                attributeNode.detach()
            }
            if attributes == nil {
                attributes = [node]
            } else {
                attributes!.append(node)
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
                attribute.parent = self
            }
        }
        
        /// return namespace attached to element
        public func namespace(forName: String?) -> XML.Node? {
            return namespaces?.first {
                if $0.name == forName {
                    return true
                }
                return false
            }
        }
        
        /// add a namespace to an element. If one with this name already exists it is replaced
        public func addNamespace(_ node : XML.Node) {
            if let attributeNode = namespace(forName: node.name) {
                attributeNode.detach()
            }
            if namespaces == nil {
                namespaces = [node]
            } else {
                namespaces!.append(node)
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
                namespace.parent = self
            }
        }

        /// detach child XML Node
        fileprivate override func detach(child: XML.Node) {
            switch child.kind {
            case .attribute:
                attributes?.removeAll(where: {$0 === child})
            case .namespace:
                namespaces?.removeAll(where: {$0 === child})
            default:
                super.detach(child: child)
            }
        }

        /// return formatted XML
        override public var xmlString : String {
            var string = ""
            string += "<\(name!)"
            string += namespaces?.map({" "+$0.xmlString}).joined(separator:"") ?? ""
            string += attributes?.map({" "+$0.xmlString}).joined(separator:"") ?? ""
            string += ">"
            for node in children ?? [] {
                string += node.xmlString
            }
            string += "</\(name!)>"
            return string
        }
    }
    
    /// XML parsing errors
    enum ParsingError : Error {
        case emptyFile
        
        var localizedDescription: String {
            switch self {
            case .emptyFile:
                return "File contained nothing"
            }
        }
    }
    
    /// parser delegate used in XML parsing
    fileprivate class ParserDelegate : NSObject, XMLParserDelegate {
        
        var rootElement : XML.Element?
        var currentElement : XML.Element?
        var error : Error?
        
        override init() {
            self.currentElement = nil
            self.rootElement = nil
            super.init()
        }
        
        func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes attributeDict: [String : String] = [:]) {
            let element = XML.Element(name: elementName)
            for attribute in attributeDict {
                element.addAttribute(XML.Node(.attribute, name: attribute.key, stringValue: attribute.value))
            }
            if rootElement ==  nil {
                rootElement = element
            }
            currentElement?.addChild(element)
            currentElement = element
        }
        
        func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
            currentElement = currentElement?.parent as? XML.Element
        }
        
        func parser(_ parser: XMLParser, foundCharacters: String) {
            currentElement?.addChild(XML.Node.text(stringValue: foundCharacters))
        }
        
        func parser(_ parser: XMLParser, foundComment comment: String) {
            currentElement?.addChild(XML.Node.comment(stringValue: comment))
        }
        
        func parser(_ parser: XMLParser, foundCDATA CDATABlock: Data) {
            currentElement?.addChild(XML.Node.text(stringValue: String(data: CDATABlock, encoding: .utf8)!))
        }
        
        func parser(_ parser: XMLParser, parseErrorOccurred parseError: Error) {
            error = parseError
        }
        
        func parser(_ parser: XMLParser, validationErrorOccurred validationError: Error) {
            error = validationError
        }
    }
    
}
