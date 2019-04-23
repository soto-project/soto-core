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

    func encodeToXMLUTF8Data(_ input: AWSShape, attributes: XMLAttribute = [:]) throws -> Data? {
        let node = try encodeToXMLNode(input, attributes: attributes)
        return XMLNodeSerializer(node: node).serializeToXML().data(using: .utf8, allowLossyConversion: false)
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
    
    func encodeToQueryDictionary(_ input: AWSShape) -> [String : Any] {
        var dictionary : [String : Any] = [:]
        
        func encodeToFlatDictionary(_ input: AWSShape, name: String? = nil) {
            let mirror = Mirror(reflecting: input)
            
            for el in mirror.children {
                guard let label = el.label?.upperFirst() else { continue }
                guard let value = unwrap(any: el.value) else { continue }
                let fullLabel = name != nil ? "\(name!).\(label)" : label
                
//                let node = XMLNode(elementName: label)
                switch value {
                case let v as AWSShape:
                    encodeToFlatDictionary(v, name:fullLabel)
                    
                case let v as [AWSShape]:
                    for iterator in v.enumerated() {
                        encodeToFlatDictionary(iterator.element, name: "\(fullLabel).member.\(iterator.offset+1)")
                    }
                    
                case let v as [AnyHashable : AWSShape]:
                    for iterator in v.enumerated() {
                        dictionary["\(fullLabel).entry.\(iterator.offset+1).key"] = iterator.element.key
                        encodeToFlatDictionary(iterator.element.value, name: "\(fullLabel).entry.\(iterator.offset+1).value")
                    }
                    
                default:
                    switch value {
                    case let v as [Any]:
                        for iterator in v.enumerated() {
                            dictionary["\(fullLabel).member.\(iterator.offset+1)"] = iterator.element
                        }
                        
                    case let v as [AnyHashable: Any]:
                        for iterator in v.enumerated() {
                            dictionary["\(fullLabel).entry.\(iterator.offset+1).key"] = iterator.element.key
                            dictionary["\(fullLabel).entry.\(iterator.offset+1).value"] = iterator.element.value
                        }
                    default:
                        dictionary[fullLabel] = value
                    }
                }
                
            }
        }
        encodeToFlatDictionary(input)
        
        return dictionary
    }
}
