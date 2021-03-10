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

import NIO
import NIOFoundationCompat
import enum SotoXML.XML

/// Enumaration used to store request/response body in various forms
public enum Body {
    /// text
    case text(String)
    /// raw data
    case raw(AWSPayload)
    /// json data
    case json(ByteBuffer)
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

        case .json(let buffer):
            return buffer.getString(at: buffer.readerIndex, length: buffer.readableBytes, encoding: .utf8)

        case .xml(let node):
            let xmlDocument = XML.Document(rootElement: node)
            return xmlDocument.xmlString

        case .empty:
            return nil
        }
    }

    /// return as payload
    public func asPayload(byteBufferAllocator: ByteBufferAllocator) -> AWSPayload {
        switch self {
        case .text(let text):
            var buffer = byteBufferAllocator.buffer(capacity: text.utf8.count)
            buffer.writeString(text)
            return .byteBuffer(buffer)

        case .raw(let payload):
            return payload

        case .json(let buffer):
            if buffer.readableBytes == 0 {
                return .empty
            } else {
                return .byteBuffer(buffer)
            }

        case .xml(let node):
            let xmlDocument = XML.Document(rootElement: node)
            let text = xmlDocument.xmlString
            var buffer = byteBufferAllocator.buffer(capacity: text.utf8.count)
            buffer.writeString(text)
            return .byteBuffer(buffer)

        case .empty:
            return .empty
        }
    }

    /// return as ByteBuffer
    public func asByteBuffer(byteBufferAllocator: ByteBufferAllocator) -> ByteBuffer? {
        return asPayload(byteBufferAllocator: byteBufferAllocator).asByteBuffer()
    }

    var isStreaming: Bool {
        if case .raw(let payload) = self, case .stream = payload.payload {
            return true
        }
        return false
    }
}
