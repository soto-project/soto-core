//
//  AWSShapeEncoder.swift
//  AWSSDKSwiftCorePackageDescription
//
//  Created by Yuki Takei on 2017/10/07.
//

import struct Foundation.Data
import class  Foundation.JSONEncoder

func unwrap(any: Any) -> Any? {
    let mi = Mirror(reflecting: any)
    if mi.displayStyle != .optional {
        return any
    }
    if mi.children.count == 0 { return nil }
    let (_, some) = mi.children.first!
    return some
}

class AWSShapeEncoder {
    public init() {}

    public func json<Input: AWSShape>(_ input: Input) throws -> Data {
        return try JSONEncoder().encode(input)
    }
    
    public func dictionary<Input: AWSShape>(_ input: Input) throws -> [String:Any] {
        return try DictionaryEncoder().encode(input)
    }
    
    public func xml<Input: AWSShape>(_ input: Input, overrideName: String? = nil) throws -> XML.Element {
        let xml = try XMLEncoder().encode(input, name: overrideName)
        if let xmlNamespace = Input._xmlNamespace {
            xml.addNamespace(XML.Node.namespace(stringValue: xmlNamespace))
        }
        return xml
    }

    public func query<Input: AWSShape>(_ input: Input, flattenArrays: Bool = false) throws -> [String : Any] {
        let encoder = QueryEncoder()
        encoder.flattenContainers = flattenArrays
        return try encoder.encode(input)
    }
}
