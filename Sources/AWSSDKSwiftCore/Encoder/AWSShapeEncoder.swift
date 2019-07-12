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

    public func json<Input: AWSShape>(_ input: Input) throws -> Data {
        return try JSONEncoder().encode(input)
    }
    
    public func dictionary<Input: AWSShape>(_ input: Input) throws -> [String:Any] {
        return try DictionaryEncoder().encode(input)
    }
    
    public func xml<Input: AWSShape>(_ input: Input, overrideName: String? = nil) throws -> XML.Element {
        return try XMLEncoder().encode(input, name: overrideName)
    }

    /// Encode shape into query keys and values
    public func query(_ input: AWSShape, flattenLists: Bool = false) -> [String : Any] {
        var dictionary : [String : Any] = [:]

        func encodeToFlatDictionary(_ input: AWSShape, name: String? = nil) {
            let mirror = Mirror(reflecting: input)

            for el in mirror.children {
                guard var label = el.label?.upperFirst() else { continue }
                guard let value = unwrap(any: el.value) else { continue }
                let member = type(of:input).getMember(named: label)
                if let location = member?.location, case .body(let locationName) = location {
                    label = locationName
                }
                let fullLabel = name != nil ? "\(name!).\(label)" : label

                switch value {
                case let v as AWSShape:
                    encodeToFlatDictionary(v, name:fullLabel)

                case let v as [AWSShape]:
                    var memberString = ""
                    if let encoding = member?.shapeEncoding {
                        if case .list(let element) = encoding, flattenLists == false {
                            memberString = "\(element)."
                        }
                    }
                    for iterator in v.enumerated() {
                        encodeToFlatDictionary(iterator.element, name: "\(fullLabel).\(memberString)\(iterator.offset+1)")
                    }

                case let v as [AnyHashable : AWSShape]:
                    var entryString = "entry."
                    var keyString = "key"
                    var valueString = "value"
                    if let encoding = member?.shapeEncoding {
                        switch encoding {
                        case .flatMap(let key, let value):
                            entryString = ""
                            keyString = "\(key)"
                            valueString = "\(value)"
                        case .map(let entry, let key, let value):
                            entryString = "\(entry)."
                            keyString = "\(key)"
                            valueString = "\(value)"
                        default:
                            break
                        }
                    }
                    for iterator in v.enumerated() {
                        dictionary["\(fullLabel).\(entryString)\(iterator.offset+1).\(keyString)"] = iterator.element.key
                        encodeToFlatDictionary(iterator.element.value, name: "\(fullLabel).\(entryString)\(iterator.offset+1).\(valueString)")
                    }

                case let v as [Any]:
                    var memberString = ""
                    if let encoding = member?.shapeEncoding, flattenLists == false {
                        if case .list(let element) = encoding {
                            memberString = "\(element)."
                        }
                    }
                    for iterator in v.enumerated() {
                        dictionary["\(fullLabel).\(memberString)\(iterator.offset+1)"] = iterator.element
                    }
                    
                case let v as [AnyHashable: Any]:
                    var entryString = "entry."
                    var keyString = "key"
                    var valueString = "value"
                    if let encoding = member?.shapeEncoding {
                        switch encoding {
                        case .flatMap(let key, let value):
                            entryString = ""
                            keyString = "\(key)"
                            valueString = "\(value)"
                        case .map(let entry, let key, let value):
                            entryString = "\(entry)."
                            keyString = "\(key)"
                            valueString = "\(value)"
                        default:
                            break
                        }
                    }
                    for iterator in v.enumerated() {
                        dictionary["\(fullLabel).\(entryString)\(iterator.offset+1).\(keyString)"] = iterator.element.key
                        dictionary["\(fullLabel).\(entryString)\(iterator.offset+1).\(valueString)"] = iterator.element.value
                    }
                
                default:
                    dictionary[fullLabel] = value
                }
            }
        }
        encodeToFlatDictionary(input)

        return dictionary
    }
}
