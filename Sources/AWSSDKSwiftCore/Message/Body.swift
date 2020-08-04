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

import enum AWSXML.XML
import struct Foundation.Data
import class Foundation.InputStream
import NIO
import NIOFoundationCompat

/// Enumaration used to store request/response body in various forms
public enum Body {
    /// text
    case text(String)
    /// raw data
    case raw(AWSPayload)
    /// json data
    case json(Data)
    /// xml
    case xml(XML.Element)
    /// empty body
    case empty
}

extension Body {
    /// return as a raw data buffer
    public func asString() -> String? {
        switch self {
        case .text(let text):
            return text

        case .raw(let payload):
            if let byteBuffer = payload.asByteBuffer() {
                return byteBuffer.getString(at: byteBuffer.readerIndex, length: byteBuffer.readableBytes, encoding: .utf8)
            } else {
                return nil
            }

        case .json(let data):
            return String(data: data, encoding: .utf8)

        case .xml(let node):
            let xmlDocument = XML.Document(rootElement: node)
            return xmlDocument.xmlString

        case .empty:
            return nil
        }
    }

    /// return as payload
    public func asPayload() -> AWSPayload {
        switch self {
        case .text(let text):
            var buffer = ByteBufferAllocator().buffer(capacity: text.utf8.count)
            buffer.writeString(text)
            return .byteBuffer(buffer)

        case .raw(let payload):
            return payload

        case .json(let data):
            if data.isEmpty {
                return .empty
            } else {
                var buffer = ByteBufferAllocator().buffer(capacity: data.count)
                buffer.writeBytes(data)
                return .byteBuffer(buffer)
            }

        case .xml(let node):
            let xmlDocument = XML.Document(rootElement: node)
            let text = xmlDocument.xmlString
            var buffer = ByteBufferAllocator().buffer(capacity: text.utf8.count)
            buffer.writeString(text)
            return .byteBuffer(buffer)

        case .empty:
            return .empty
        }
    }

    // return as ByteBuffer
    public func asByteBuffer() -> ByteBuffer? {
        return asPayload().asByteBuffer()
    }
}
