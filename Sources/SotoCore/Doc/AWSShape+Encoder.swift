//===----------------------------------------------------------------------===//
//
// This source file is part of the Soto for AWS open source project
//
// Copyright (c) 2017-2020 the Soto project authors
// Licensed under Apache License v2.0
//
// See LICENSE.txt for license information
// See CONTRIBUTORS.txt for the list of Soto project authors
//
// SPDX-License-Identifier: Apache-2.0
//
//===----------------------------------------------------------------------===//

import class Foundation.JSONEncoder
import NIO
import SotoXML

internal extension AWSEncodableShape {
    /// Encode AWSShape as JSON
    func encodeAsJSON(byteBufferAllocator: ByteBufferAllocator) throws -> ByteBuffer {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        return try encoder.encodeAsByteBuffer(self, allocator: byteBufferAllocator)
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
    func encodeAsQuery(with keys: [String: String]) throws -> String? {
        var encoder = QueryEncoder()
        encoder.additionalKeys = keys
        return try encoder.encode(self)
    }

    /// Encode AWSShape as a query array
    func encodeAsQueryForEC2(with keys: [String: String]) throws -> String? {
        var encoder = QueryEncoder()
        encoder.additionalKeys = keys
        encoder.ec2 = true
        return try encoder.encode(self)
    }
}
