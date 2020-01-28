//
//  Body.swift
//  AWSSDKSwift
//
//  Created by Yuki Takei on 2017/04/11.
//
//

import NIO
import struct Foundation.Data
import class  Foundation.InputStream
import class  Foundation.JSONSerialization

/// Enumaration used to store request/response body in various forms
public enum Body {
    /// text
    case text(String)
    /// raw data
    case buffer(Data)
    /// json data
    case json(Data)
    /// xml
    case xml(XML.Element)
    /// empty body
    case empty
}

extension Body {
    /// initialize Body with Any. If it is Data, create .buffer() otherwise create a String describing the value
    init(anyValue: Any) {
        switch anyValue {
        case let v as Data:
            self = .buffer(v)
        default:
            self = .text("\(anyValue)")
        }
    }

    /// return as a raw data buffer
    public func asString() -> String? {
        switch self {
        case .text(let text):
            return text

        case .buffer(let data):
            return String(data: data, encoding: .utf8)

        case .json(let data):
            return String(data: data, encoding: .utf8)

        case .xml(let node):
            let xmlDocument = XML.Document(rootElement: node)
            return xmlDocument.xmlString

        case .empty:
            return nil
        }
    }

    /// return as bytebuffer
    public func asByteBuffer() -> ByteBuffer? {
        switch self {
        case .text(let text):
            var buffer = ByteBufferAllocator().buffer(capacity: text.utf8.count)
            buffer.writeString(text)
            return buffer

        case .buffer(let data):
            var buffer = ByteBufferAllocator().buffer(capacity: data.count)
            buffer.writeBytes(data)
            return buffer

        case .json(let data):
            if data.isEmpty {
                return nil
            } else {
                var buffer = ByteBufferAllocator().buffer(capacity: data.count)
                buffer.writeBytes(data)
                return buffer
            }

        case .xml(let node):
            let xmlDocument = XML.Document(rootElement: node)
            let text = xmlDocument.xmlString
            var buffer = ByteBufferAllocator().buffer(capacity: text.utf8.count)
            buffer.writeString(text)
            return buffer

        case .empty:
            return nil
        }
    }
}
