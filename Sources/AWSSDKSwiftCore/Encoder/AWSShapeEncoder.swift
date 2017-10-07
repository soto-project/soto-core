//
//  AWSShapeEncoder.swift
//  AWSSDKSwiftCorePackageDescription
//
//  Created by Yuki Takei on 2017/10/07.
//

import Foundation

func unwrap(any: Any) -> Any? {
    let mi = Mirror(reflecting: any)
    if mi.displayStyle != .optional {
        return any
    }
    if mi.children.count == 0 { return nil }
    let (_, some) = mi.children.first!
    return some
}

public typealias XMLAttribute = [String: [String: String]] // ["elementName": ["key": "value", ...]]

private let sharedJSONEncoder = JSONEncoder()
private let sharedAWSShapeEncoder = AWSShapeEncoder()

struct AWSShapeEncoder {
    func encodeToJSONUTF8Data<Input: AWSShape>(_ input: Input) throws -> Data {
        return try sharedJSONEncoder.encode(input)
    }
    
    func encodeToXMLUTF8Data(_ input: AWSShape, attributes: XMLAttribute = [:]) throws -> Data {
        let node = try encodeToXMLNode(input, attributes: attributes)
        return XMLNodeSerializer(node: node).serializeToXML().data
    }
    
    func encodeToXMLNode(_ input: AWSShape, attributes: XMLAttribute = [:]) throws -> XMLNode {
        let mirror = Mirror(reflecting: input)
        let name = "\(mirror.subjectType)"
        let xmlNode = XMLNode(elementName: name.upperFirst())
        if let attr = attributes.filter({ $0.key == name }).first {
            xmlNode.attributes = attr.value
        }
        
        for el in mirror.children {
            guard let label = el.label?.upperFirst() else {
                continue
            }
            
            guard let value = unwrap(any: el.value) else {
                continue
            }
            let node = XMLNode(elementName: label)
            switch value {
            case let v as AWSShape:
                let cNode = try AWSShapeEncoder().encodeToXMLNode(v)
                node.children.append(contentsOf: cNode.children)
                
            case let v as [AWSShape]:
                for vv in v {
                    let cNode = try AWSShapeEncoder().encodeToXMLNode(vv)
                    node.children.append(contentsOf: cNode.children)
                }
                
            default:
                switch value {
                case let v as [Any]:
                    for vv in v {
                        node.values.append("\(vv)")
                    }
                    
                case let v as [AnyHashable: Any]:
                    for (key, value) in v {
                        let cNode = XMLNode(elementName: "\(key)")
                        cNode.values.append("\(value)")
                        node.children.append(cNode)
                    }
                default:
                    node.values.append("\(value)")
                }
            }
            
            xmlNode.children.append(node)
        }
        
        return xmlNode
    }
}
