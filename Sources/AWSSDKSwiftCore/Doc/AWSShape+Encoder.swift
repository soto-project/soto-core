//===----------------------------------------------------------------------===//
//
// This source file is part of the AWSSDKSwift open source project
//
// Copyright (c) 2017-2020 the AWSSDKSwift project authors
// Licensed under Apache License v2.0
//
// See LICENSE.txt for license information
// See CONTRIBUTORS.txt for the list of AWSSDKSwift project authors
//
// SPDX-License-Identifier: Apache-2.0
//
//===----------------------------------------------------------------------===//

import struct Foundation.Data
import class  Foundation.JSONEncoder

internal extension AWSShape {
    
    /// Encode AWSShape as JSON
    func encodeAsJSON() throws -> Data {
        return try JSONEncoder().encode(self)
    }
    
    /// Encode AWSShape as XML
    func encodeAsXML(rootName: String? = nil) throws -> XML.Element {
        let xml = try XMLEncoder().encode(self, name: rootName)
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

