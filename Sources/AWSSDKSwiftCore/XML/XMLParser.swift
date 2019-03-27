//
//  XMLParser.swift
//  AWSSDKSwift
//
//  Created by Yuki Takei on 2017/04/04.
//
//

import Foundation

public enum XML2ParserError: Error {
    case failedToParse(Data)
}

public class XML2Parser: NSObject, XMLParserDelegate {
    
    private let parser: XMLParser
    
    private let data: Data
    
    private var error: Error?
    
    private var nodeTree: XMLNode?
    
    private var currentNode: XMLNode?
    
    private var lastElementName: String?
    
    private var currentNodeIsArray = false
    
    public init(data: Data) {
        self.data = data
        self.parser = XMLParser(data: data)
        super.init()
        self.parser.delegate = self
    }
    
    public func parse() throws -> XMLNode {
        _ = parser.parse()
        if let nodeTree = nodeTree {
            return nodeTree
        }
        throw XML2ParserError.failedToParse(data)
    }
    
    public func parser(_ parser: XMLParser, foundCharacters string: String) {
        let string = string.trimmingCharacters(in: .whitespacesAndNewlines)
        if !string.isEmpty && string != "\"" {
            if currentNode?.values.count == 0 || currentNodeIsArray {
                currentNode?.values.append(string)
            } else {
                if let first = currentNode?.values.first {
                    currentNode?.values[0] = first+string
                }
            }
        }
    }
    
    public func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes attributeDict: [String : String] = [:]) {
        let elementName = elementName.upperFirst()
        let node = XMLNode(elementName: elementName)
        node.attributes = attributeDict
        
        currentNodeIsArray = lastElementName == elementName
        
        if nodeTree == nil {
            nodeTree = node
        } else {
            node.parent = currentNode
            currentNode?.children.append(node)
        }
        
        currentNode = node
    }
    
    public func parser(_ parser: XMLParser, parseErrorOccurred parseError: Error) {
        self.error = parseError
    }
    
    public func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
        if let currentElementName = currentNode?.elementName, currentElementName.lowercased() == elementName.lowercased() {
            currentNode = currentNode?.parent
        }
        lastElementName = elementName.upperFirst()
    }
}
