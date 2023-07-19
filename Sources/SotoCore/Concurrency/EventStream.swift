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

enum AWSEventStreamError: Error {
    case corruptHeader
    case corruptPayload
}

private enum InternalAWSEventStreamError: Error {
    case needMoreData
}

public struct AWSEventStream<Event: Sendable>: Sendable {
    let base: AnyAsyncSequence<ByteBuffer>
}

extension AWSEventStream: AsyncSequence where Event: Decodable {
    public typealias Element = Event

    public struct AsyncIterator: AsyncIteratorProtocol {
        enum State {
            case idle
            case readingEvent(ByteBuffer)
        }

        var baseIterator: AnyAsyncSequence<ByteBuffer>.AsyncIterator
        var state: State = .idle

        public mutating func next() async throws -> Event? {
            while var buffer = try await baseIterator.next() {
                switch self.state {
                case .idle:
                    if let event = try readEvent(buffer) {
                        return event
                    } else {
                        self.state = .readingEvent(buffer)
                    }
                case .readingEvent(var prevBuffer):
                    prevBuffer.writeBuffer(&buffer)
                    if let event = try readEvent(prevBuffer) {
                        return event
                    } else {
                        self.state = .readingEvent(prevBuffer)
                    }
                }
            }
            return nil
        }

        func readEvent(_ buffer: ByteBuffer) throws -> Event? {
            do {
                let event = try EventStreamDecoder().decode(Event.self, from: buffer)
                return event
            } catch InternalAWSEventStreamError.needMoreData {
                return nil
            }
        }
    }

    public func makeAsyncIterator() -> AsyncIterator {
        .init(baseIterator: self.base.makeAsyncIterator())
    }
}

struct EventStreamDecoder {
    public init() {}

    public func decode<T: Decodable>(_ type: T.Type, from buffer: ByteBuffer) throws -> T {
        let decoder = _EventStreamDecoder(buffer: buffer)
        let value = try T(from: decoder)
        return value
    }
}

private struct _EventStreamDecoder: Decoder {
    var codingPath: [CodingKey] { [] }
    var userInfo: [CodingUserInfoKey: Any] { [:] }

    let buffer: ByteBuffer

    func container<Key>(keyedBy type: Key.Type) throws -> KeyedDecodingContainer<Key> where Key: CodingKey {
        let (headers, payload) = try readEvent(self.buffer)
        return KeyedDecodingContainer(KDC<Key>(headers: headers, payload: payload))
    }

    struct KDC<Key: CodingKey>: KeyedDecodingContainerProtocol {
        var codingPath: [CodingKey] { [] }
        var allKeys: [Key] { self.eventTypeKey.map { [$0] } ?? [] }
        let eventTypeKey: Key?
        let headers: [String: String]
        let payload: ByteBuffer

        init(headers: [String: String], payload: ByteBuffer) {
            self.headers = headers
            self.payload = payload
            self.eventTypeKey = self.headers[":event-type"].map { .init(stringValue: $0) } ?? nil
        }

        func contains(_ key: Key) -> Bool {
            self.eventTypeKey?.stringValue == key.stringValue
        }

        func decodeNil(forKey key: Key) throws -> Bool {
            return true
        }

        func decode<T>(_ type: T.Type, forKey key: Key) throws -> T where T: Decodable {
            let jsonDecoder = JSONDecoder()
            jsonDecoder.dateDecodingStrategy = .secondsSince1970
            jsonDecoder.userInfo[.awsEvent] = EventDecodingContainer(payload: self.payload)
            return try jsonDecoder.decode(T.self, from: .init(staticString: "{}"))
        }

        func nestedContainer<NestedKey>(keyedBy type: NestedKey.Type, forKey key: Key) throws -> KeyedDecodingContainer<NestedKey> where NestedKey: CodingKey {
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

    func readEvent(_ byteBuffer: ByteBuffer) throws -> ([String: String], ByteBuffer) {
        var byteBuffer = byteBuffer
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

        // get prelude buffer and crc. Return nil if we don't have enough data
        guard var preludeBuffer = byteBuffer.getSlice(at: byteBuffer.readerIndex, length: 8) else { throw InternalAWSEventStreamError.needMoreData }
        guard let preludeCRC: UInt32 = byteBuffer.getInteger(at: byteBuffer.readerIndex + 8) else { throw InternalAWSEventStreamError.needMoreData }
        // verify crc
        let calculatedPreludeCRC = soto_crc32(0, bytes: ByteBufferView(preludeBuffer))
        guard UInt(preludeCRC) == calculatedPreludeCRC else { throw AWSEventStreamError.corruptPayload }
        // get lengths
        guard let totalLength: Int32 = preludeBuffer.readInteger(),
              let headerLength: Int32 = preludeBuffer.readInteger() else { throw InternalAWSEventStreamError.needMoreData }

        // get message and message CRC. Return nil if we don't have enough data
        guard var messageBuffer = byteBuffer.readSlice(length: Int(totalLength - 4)),
              let messageCRC: UInt32 = byteBuffer.readInteger() else { throw InternalAWSEventStreamError.needMoreData }
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
        /* if headers[":message-type"] == "error" {
             throw S3SelectError.selectContentError(headers[":error-code"] ?? "Unknown")
         } */

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

public struct EventDecodingContainer {
    let payload: ByteBuffer

    public func decodePayload() -> ByteBuffer {
        return self.payload
    }
}

extension CodingUserInfoKey {
    public static var awsEvent: Self { return .init(rawValue: "soto.awsEvent")! }
}
