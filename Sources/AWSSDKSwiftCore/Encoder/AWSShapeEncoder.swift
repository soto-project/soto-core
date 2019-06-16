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

public struct AWSShapeEncoder {
    public init() {}

    func json<Input: AWSShape>(_ input: Input) throws -> Data {
        return try JSONEncoder().encode(input)
    }
    
    func dictionary<Input: AWSShape>(_ input: Input) throws -> [String:Any] {
        return try DictionaryEncoder().encode(input)
    }
    
    public func xml<Input: AWSShape>(_ input: Input, overrideName: String? = nil) throws -> XMLElement {
        return try XMLEncoder().encode(input, name: overrideName)
    }

    /// Encode shape into query keys and values
    func query(_ input: AWSShape) -> [String : Any] {
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
