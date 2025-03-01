//===----------------------------------------------------------------------===//
//
// This source file is part of the Soto for AWS open source project
//
// Copyright (c) 2023 the Soto project authors
// Licensed under Apache License v2.0
//
// See LICENSE.txt for license information
// See CONTRIBUTORS.txt for the list of Soto project authors
//
// SPDX-License-Identifier: Apache-2.0
//
//===----------------------------------------------------------------------===//

import Foundation
import NIOCore

#if compiler(>=5.10)
internal import SotoXML
#else
@_implementationOnly import SotoXML
#endif

/// Event stream decoder. Decodes top level `:event-type` header and then passes the payload
/// to another decoder based off the `:content-type` header
struct EventStreamDecoder {
    init() {}

    func decode<T: Decodable>(_ type: T.Type, from buffer: inout ByteBuffer) throws -> T {
        let decoder = try _EventStreamDecoder(buffer: &buffer)
        let value = try T(from: decoder)
        return value
    }
}

/// Internal implementation of `EventStreamDecoder`
private struct _EventStreamDecoder: Decoder {
    var codingPath: [CodingKey] { [] }
    var userInfo: [CodingUserInfoKey: Any] { [:] }
    let headers: [String: String]
    let payload: ByteBuffer

    init(buffer: inout ByteBuffer) throws {
        let (headers, payload) = try Self.readEvent(&buffer)
        self.headers = headers
        self.payload = payload
    }

    func container<Key>(keyedBy type: Key.Type) throws -> KeyedDecodingContainer<Key> where Key: CodingKey {
        KeyedDecodingContainer(try KDC<Key>(headers: self.headers, payload: self.payload))
    }

    struct KDC<Key: CodingKey>: KeyedDecodingContainerProtocol {
        var codingPath: [CodingKey] { [] }
        let allKeys: [Key]
        let headers: [String: String]
        let payload: ByteBuffer

        init(headers: [String: String], payload: ByteBuffer) throws {
            self.headers = headers
            self.payload = payload

            switch headers[":message-type"] {
            case "event":
                guard let eventTypeKey = headers[":event-type"].flatMap(Key.init) else {
                    throw AWSEventStreamError.missingHeader(":event-type")
                }
                self.allKeys = [eventTypeKey]
            case "exception":
                guard let exceptionTypeKey = headers[":exception-type"].flatMap(Key.init) else {
                    throw AWSEventStreamError.missingHeader(":exception-type")
                }
                self.allKeys = [exceptionTypeKey]
            case "error":
                guard let errorCode = headers[":error-code"] else {
                    throw AWSEventStreamError.missingHeader(":error-code")
                }
                throw AWSEventStreamError.errorMessage(errorCode, headers[":error-message"])
            case .none:
                throw AWSEventStreamError.missingHeader(":message-type")
            case .some(let messageType):
                throw AWSEventStreamError.unknownMessageType(messageType)
            }
        }

        func contains(_ key: Key) -> Bool {
            self.allKeys.contains { $0.stringValue == key.stringValue }
        }

        func decodeNil(forKey key: Key) throws -> Bool {
            true
        }

        func decode<T>(_ type: T.Type, forKey key: Key) throws -> T where T: Decodable {
            switch self.headers[":content-type"] {
            case "application/json":
                let jsonDecoder = JSONDecoder()
                jsonDecoder.dateDecodingStrategy = .secondsSince1970
                jsonDecoder.userInfo[.awsEvent] = EventDecodingContainer(payload: self.payload)
                return try jsonDecoder.decode(T.self, from: self.payload)

            case "text/xml", "application/xml":
                let xmlDocument = try XML.Document(buffer: self.payload)
                let xmlElement = xmlDocument.rootElement() ?? .init(name: "__empty_element")

                var xmlDecoder = XMLDecoder()
                xmlDecoder.userInfo[.awsEvent] = EventDecodingContainer(payload: self.payload)
                return try xmlDecoder.decode(T.self, from: xmlElement)

            case "application/octet-stream":
                // if content-type is a raw buffer then use JSONDecoder() to pass this to `init(from:)`
                // via the user info`
                let jsonDecoder = JSONDecoder()
                jsonDecoder.dateDecodingStrategy = .secondsSince1970
                jsonDecoder.userInfo[.awsEvent] = EventDecodingContainer(payload: self.payload)
                return try jsonDecoder.decode(T.self, from: .init(staticString: "{}"))

            case .none:
                // if there is no content-type then create object using JSONDecoder() and some empty json
                return try JSONDecoder().decode(T.self, from: .init(staticString: "{}"))

            case .some(let header):
                throw AWSEventStreamError.unsupportedContentType(header)
            }
        }

        func nestedContainer<NestedKey>(keyedBy type: NestedKey.Type, forKey key: Key) throws -> KeyedDecodingContainer<NestedKey>
        where NestedKey: CodingKey {
            preconditionFailure("Nested containers are not supported")
        }

        func nestedUnkeyedContainer(forKey key: Key) throws -> UnkeyedDecodingContainer {
            preconditionFailure("Nested unkeyed containers are not supported")
        }

        func superDecoder() throws -> Decoder {
            preconditionFailure("Super decoders are not supported")
        }

        func superDecoder(forKey key: Key) throws -> Decoder {
            preconditionFailure("Super decoders are not supported")
        }
    }

    /// Read event from ByteBuffer. See https://docs.aws.amazon.com/AmazonS3/latest/API/RESTSelectObjectAppendix.html for more details
    /// - Parameter byteBuffer: ByteBuffer containing event
    /// - Returns: Headers and event payload
    static func readEvent(_ byteBuffer: inout ByteBuffer) throws -> ([String: String], ByteBuffer) {
        // read header values from ByteBuffer. Format is uint8 name length, name, 7, uint16 value length, value
        func readHeaderValues(_ byteBuffer: ByteBuffer) throws -> [String: String] {
            var byteBuffer = byteBuffer
            var headers: [String: String] = [:]
            while byteBuffer.readableBytes > 0 {
                guard let headerLength: UInt8 = byteBuffer.readInteger(),
                    let header: String = byteBuffer.readString(length: Int(headerLength)),
                    let byte: UInt8 = byteBuffer.readInteger(), byte == 7,
                    let valueLength: UInt16 = byteBuffer.readInteger(),
                    let value: String = byteBuffer.readString(length: Int(valueLength))
                else {
                    throw AWSEventStreamError.corruptHeader
                }
                headers[header] = value
            }
            return headers
        }

        guard byteBuffer.readableBytes > 0 else { throw InternalAWSEventStreamError.needMoreData }

        // get prelude buffer and crc. Throw `needMoreData` if we don't have enough data
        guard var preludeBuffer = byteBuffer.getSlice(at: byteBuffer.readerIndex, length: 8) else { throw InternalAWSEventStreamError.needMoreData }
        guard let preludeCRC: UInt32 = byteBuffer.getInteger(at: byteBuffer.readerIndex + 8) else { throw InternalAWSEventStreamError.needMoreData }
        // verify crc
        let calculatedPreludeCRC = soto_crc32(0, bytes: ByteBufferView(preludeBuffer))
        guard UInt(preludeCRC) == calculatedPreludeCRC else { throw AWSEventStreamError.corruptPayload }
        // get lengths
        guard let totalLength: Int32 = preludeBuffer.readInteger(),
            let headerLength: Int32 = preludeBuffer.readInteger()
        else { throw InternalAWSEventStreamError.needMoreData }

        // get message and message CRC. Throw `needMoreData` if we don't have enough data
        guard var messageBuffer = byteBuffer.readSlice(length: Int(totalLength - 4)),
            let messageCRC: UInt32 = byteBuffer.readInteger()
        else { throw InternalAWSEventStreamError.needMoreData }
        // verify message CRC
        let calculatedCRC = soto_crc32(0, bytes: ByteBufferView(messageBuffer))
        guard UInt(messageCRC) == calculatedCRC else { throw AWSEventStreamError.corruptPayload }

        // skip past prelude
        messageBuffer.moveReaderIndex(forwardBy: 12)

        // get headers
        guard let headerBuffer: ByteBuffer = messageBuffer.readSlice(length: Int(headerLength)) else {
            throw AWSEventStreamError.corruptHeader
        }
        let headers = try readHeaderValues(headerBuffer)

        let payloadSize = Int(totalLength - headerLength - 16)
        let payloadBuffer = messageBuffer.readSlice(length: payloadSize)

        return (headers, payloadBuffer ?? .init())
    }

    func unkeyedContainer() throws -> UnkeyedDecodingContainer {
        preconditionFailure("Unkeyed containers are not supported")
    }

    func singleValueContainer() throws -> SingleValueDecodingContainer {
        preconditionFailure("Single value containers are not supported")
    }
}

/// Container used for passed event payload to decoders
struct EventDecodingContainer {
    let payload: ByteBuffer

    /// Return payload from EventStream payload
    /// - Returns: Payload as ByteBuffer
    func decodePayload() -> ByteBuffer {
        self.payload
    }
}

extension CodingUserInfoKey {
    /// AWS Event user info key
    public static var awsEvent: Self { .init(rawValue: "soto.awsEvent")! }
}

/// Errors thrown while decoding the event stream buffers
public struct AWSEventStreamError: Error {
    public struct Code: Sendable {
        enum _Internal {
            case corruptHeader
            case missingHeader
            case corruptPayload
            case errorMessage
            case unsupportedContentType
            case unknownMessageType
        }

        private let value: _Internal

        /// The message headers are corrupt
        public static var corruptHeader: Self { .init(value: .corruptHeader) }
        /// An event stream message headers is missing
        public static var missingHeader: Self { .init(value: .missingHeader) }
        /// The message payload is corrupt
        public static var corruptPayload: Self { .init(value: .corruptPayload) }
        /// The message was an error
        public static var errorMessage: Self { .init(value: .errorMessage) }
        /// Unsupported content type
        public static var unsupportedContentType: Self { .init(value: .unsupportedContentType) }
        /// Unknown message type
        public static var unknownMessageType: Self { .init(value: .unknownMessageType) }
    }
    public let code: Code
    public let message: String?

    init(code: Code, message: String? = nil) {
        self.code = code
        self.message = message
    }

    /// The message headers are corrupt
    public static var corruptHeader: Self { .init(code: .corruptHeader) }
    /// An event stream message headers is missing
    public static func missingHeader(_ header: String) -> Self {
        .init(code: .missingHeader, message: "Eventstream header '\(header)' is missing")
    }
    /// The message payload is corrupt
    public static var corruptPayload: Self { .init(code: .corruptPayload) }
    /// The message was an error
    public static func errorMessage(_ errorCode: String, _ errorMessage: String?) -> Self {
        .init(code: .errorMessage, message: "Eventstream Error: \(errorCode)\(errorMessage.map { " \($0)" } ?? "")")
    }
    /// Unsupported content type
    public static func unsupportedContentType(_ contentType: String) -> Self {
        .init(code: .unsupportedContentType, message: "Unsupported content-type '\(contentType)'")
    }
    /// Unknown message type
    public static func unknownMessageType(_ messageType: String) -> Self {
        .init(code: .unknownMessageType, message: "Unknown message type '\(messageType)'")
    }
}

/// Internal error used to indicate we need more data to parse this message
internal enum InternalAWSEventStreamError: Error {
    case needMoreData
}
