//===----------------------------------------------------------------------===//
//
// This source file is part of the Soto for AWS open source project
//
// Copyright (c) 2017-2023 the Soto project authors
// Licensed under Apache License v2.0
//
// See LICENSE.txt for license information
// See CONTRIBUTORS.txt for the list of Soto project authors
//
// SPDX-License-Identifier: Apache-2.0
//
//===----------------------------------------------------------------------===//

import class Foundation.JSONEncoder
import NIOCore
@_implementationOnly import SotoXML

internal extension AWSEncodableShape {
    /// Encode AWSShape as JSON
    func encodeAsJSON(byteBufferAllocator: ByteBufferAllocator, container: RequestEncodingContainer) throws -> ByteBuffer {
        let encoder = JSONEncoder()
        encoder.userInfo[.awsRequest] = container
        encoder.dateEncodingStrategy = .secondsSince1970
        return try encoder.encodeAsByteBuffer(self, allocator: byteBufferAllocator)
    }

    /// Encode AWSShape as XML
    func encodeAsXML(rootName: String? = nil, namespace: String?, container: RequestEncodingContainer) throws -> String {
        var encoder = XMLEncoder()
        encoder.userInfo[.awsRequest] = container
        let xml = try encoder.encode(self, name: rootName)
        if let xmlNamespace = Self._xmlNamespace ?? namespace {
            xml.addNamespace(XML.Node.namespace(stringValue: xmlNamespace))
        }
        let document = XML.Document(rootElement: xml)
        return document.xmlString
    }

    /// Encode AWSShape as a query array
    func encodeAsQuery(with keys: [String: String], container: RequestEncodingContainer) throws -> String? {
        var encoder = QueryEncoder()
        encoder.userInfo[.awsRequest] = container
        encoder.additionalKeys = keys
        return try encoder.encode(self)
    }

    /// Encode AWSShape as a query array
    func encodeAsQueryForEC2(with keys: [String: String], container: RequestEncodingContainer) throws -> String? {
        var encoder = QueryEncoder()
        encoder.userInfo[.awsRequest] = container
        encoder.additionalKeys = keys
        encoder.ec2 = true
        return try encoder.encode(self)
    }
}
