//
//  XMLNodeSerializer.swift
//  AWSSDKSwift
//
//  Created by Yuki Takei on 2017/04/07.
//
//

import Foundation

private func dquote(_ str: String) -> String {
    if str.isEmpty {
        return ""
    }

    if str.first == "\"" && str.last == "\"" {
        return str
    }

    return "\"\(str)\""
}

private func formatAsJSONValue(_ str: String) -> String {
    return dquote(str)
}

public class XMLNodeSerializer {

    let node: XMLNode

    public init(node: XMLNode) {
        self.node = node
    }

    public func serializeToXML() -> String {
        var xmlStr = ""

        func _serialize(nodeTree: [XMLNode]) {
            for node in nodeTree {

                var attr = ""
                if !node.attributes.isEmpty {
                    attr = " " + node.buildAttributes()
                }

                if node.hasArrayValue() {
                    for value in node.values {
                        xmlStr += "<\(node.elementName)\(attr)>\(value)</\(node.elementName)>"
                    }
                }

                if node.hasSingleValue() {
                    xmlStr += "<\(node.elementName)\(attr)>\(node.values[0])</\(node.elementName)>"
                }

                if node.hasChildren() {
                    xmlStr += "<\(node.elementName)\(attr)>"
                    _serialize(nodeTree: node.children)
                    xmlStr += "</\(node.elementName)>"
                }
            }
        }

        _serialize(nodeTree: [node])

        return xmlStr
    }

    public func serializeToJSON() -> String {

        func _serialize(nodeTree: [XMLNode]) -> String {
            var jsonStr = ""

            for (index, node) in nodeTree.enumerated() {
                jsonStr += dquote(node.elementName) + ":"
                jsonStr += _serializeValue(node: node)
                if nodeTree.count-index > 1 { jsonStr+="," }
            }

            return jsonStr
        }

        func _serializeValue(node: XMLNode) -> String {
            var jsonStr = ""
            if node.hasArrayValue() {
                jsonStr += "[" +  node.values.map({ formatAsJSONValue($0) }).joined(separator: ",") + "]"
            }
            
            if node.hasSingleValue() {
                jsonStr += formatAsJSONValue(node.values[0])
            }
            
            if node.hasChildren() {
                var grouped: [String: [XMLNode]] = [:]
                node.children.forEach {
                    if grouped[$0.elementName] == nil { grouped[$0.elementName] = [] }
                    grouped[$0.elementName]?.append($0)
                }
                let arrayNodes = grouped.filter({ $0.value.count > 1 })
                let keys = arrayNodes.map({ $0.key })
                
                if let memberNode = node.children.first, memberNode.elementName.lowerFirst() == "member" {
                    _processNodeWithMember(node, memberNode, &jsonStr, arrayNodes, keys)
                } else if let memberNode = node.children.first, memberNode.elementName.lowerFirst() == "entry" {
                    _processNodeWithEntry(node, memberNode, &jsonStr, arrayNodes, keys)
                } else {
                    _processNodeWithChildren(node, &jsonStr, arrayNodes, keys)
                }
            }
            return jsonStr
        }
        
        func _processNodeWithMember(_ node: XMLNode, _ memberNode: XMLNode, _ jsonStr: inout String, _ arrayNodes: [String: [XMLNode]], _ keys: [String]) {
            let memberChildren: [XMLNode]
            
            if arrayNodes.isEmpty {
                if memberNode.children.isEmpty {
                    jsonStr += "["
                    jsonStr.append(contentsOf: memberNode.values.flatMap(formatAsJSONValue))
                    jsonStr += "]"
                } else {
                    jsonStr += "{"
                    memberChildren = memberNode.children.filter({ !keys.contains($0.elementName) })
                    jsonStr += _serialize(nodeTree: memberChildren)
                    jsonStr += "}"
                }
            } else {
                memberChildren = node.children.filter({ !keys.contains($0.elementName) })
                for (_, nodes) in arrayNodes {
                    jsonStr += "["
                    if nodes.isStructedArray() {
                        jsonStr += (nodes.map({ "{" + _serialize(nodeTree: $0.children) + "}"  }).joined(separator: ","))
                    } else {
                        jsonStr += nodes.flatMap({ $0.values }).map({ formatAsJSONValue($0) }).joined(separator: ",")
                    }
                    jsonStr += "]"
                    if memberChildren.count > 0 { jsonStr += "," }
                }
            }
        }
        
        func _processNodeWithEntry(_ node: XMLNode, _ memberNode: XMLNode, _ jsonStr: inout String, _ arrayNodes: [String: [XMLNode]], _ keys: [String]) {
            let memberChildren: [XMLNode]
            
            if arrayNodes.isEmpty {
                if memberNode.children.isEmpty {
                    jsonStr += "["
                    jsonStr.append(contentsOf: memberNode.values.flatMap(formatAsJSONValue))
                    jsonStr += "]"
                } else {
                    jsonStr += "{"
                    memberChildren = memberNode.children.filter({ !keys.contains($0.elementName) })
                    jsonStr += _serialize(nodeTree: memberChildren)
                    jsonStr += "}"
                }
            } else {
                memberChildren = node.children.filter({ !keys.contains($0.elementName) })
                for (_, nodes) in arrayNodes {
                    jsonStr += "{"
                    let keyValuePairs = nodes.map({ return (key: $0.children.first(where:{$0.elementName.lowerFirst() == "key"}), value: $0.children.first(where:{$0.elementName.lowerFirst() == "value"})) })
                    let validKeyValuePairs = keyValuePairs.filter({ ($0.key != nil && $0.value != nil)})
                    jsonStr += validKeyValuePairs.map({"\(_serializeValue(node:$0.key!)):\(_serializeValue(node:$0.value!))"}).joined(separator: ",")
                    jsonStr += "}"
                    if memberChildren.count > 0 { jsonStr += "," }
                }
            }
        }
        
        func _processNodeWithChildren(_ node: XMLNode, _ jsonStr: inout String, _ arrayNodes: [String: [XMLNode]], _ keys: [String]) {
            jsonStr += "{"
            let newChildren = node.children.filter({ !keys.contains($0.elementName) })

            for (element, nodes) in arrayNodes {
                jsonStr += "\(dquote(element)):["
                if nodes.isStructedArray() {
                    jsonStr += (nodes.map({ "{" + _serialize(nodeTree: $0.children) + "}"  }).joined(separator: ","))
                } else {
                    jsonStr += nodes.flatMap({ $0.values }).map({ formatAsJSONValue($0) }).joined(separator: ",")
                }
                jsonStr += "]"
                if newChildren.count > 0 { jsonStr += "," }
            }

            jsonStr += _serialize(nodeTree: newChildren)
            jsonStr += "}"
        }

        return ("{" + _serialize(nodeTree: [node]) + "}").replacingOccurrences(of: "\n", with: "", options: .regularExpression)

    }


}

extension Collection where Self.Iterator.Element == XMLNode {
    func isStructedArray() -> Bool {
        if let hasChildren = self.first?.hasChildren() {
            return hasChildren
        }
        return false
    }
}
