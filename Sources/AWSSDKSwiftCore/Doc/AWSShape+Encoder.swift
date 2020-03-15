//
//  AWSShapeEncoder.swift
//  AWSSDKSwiftCorePackageDescription
//
//  Created by Yuki Takei on 2017/10/07.
//

import struct Foundation.Data
import class  Foundation.JSONEncoder

internal extension AWSShape {
    
    /// Encode AWSShape as JSON
    func encodeAsJSON() throws -> Data {
        return try JSONEncoder().encode(self)
    }
    
    /// Encode AWSShape as XML
    func encodeAsXML() throws -> XML.Element {
        let xml = try XMLEncoder().encode(self)
        if let xmlNamespace = Self._xmlNamespace {
            xml.addNamespace(XML.Node.namespace(stringValue: xmlNamespace))
        }
        return xml
    }
    
    /// Encode AWSShape as a query array
    /// - Parameter flattenArrays: should all arrays be flattened
    func encodeAsQuery(flattenArrays: Bool = false) throws -> [String : Any] {
        let encoder = QueryEncoder()
        encoder.flattenContainers = flattenArrays
        return try encoder.encode(self)
    }

}

