//===----------------------------------------------------------------------===//
//
// This source file is part of the Soto for AWS open source project
//
// Copyright (c) 2017-2024 the Soto project authors
// Licensed under Apache License v2.0
//
// See LICENSE.txt for license information
// See CONTRIBUTORS.txt for the list of Soto project authors
//
// SPDX-License-Identifier: Apache-2.0
//
//===----------------------------------------------------------------------===//

import Crypto
import struct Foundation.Data
import struct Foundation.Date
import class Foundation.JSONEncoder
import struct Foundation.URL
import NIOCore
import NIOFoundationCompat
import NIOHTTP1
import SotoSignerV4
@_implementationOnly import SotoXML

/// Object encapsulating all the information needed to generate a raw HTTP request to AWS
public struct AWSHTTPRequest {
    /// request URL
    public var url: URL
    /// request HTTP method
    public let method: HTTPMethod
    /// request headers
    public var headers: HTTPHeaders
    /// request body
    public var body: AWSHTTPBody

    public init(url: URL, method: HTTPMethod, headers: HTTPHeaders, body: AWSHTTPBody) {
        self.url = url
        self.method = method
        self.headers = headers
        self.body = body
    }

    /// Create signed headers for request
    mutating func signHeaders(signer: AWSSigner, serviceConfig: AWSServiceConfig) {
        guard !signer.credentials.isEmpty() else { return }
        let payload = self.body
        let bodyDataForSigning: AWSSigner.BodyData?
        switch payload.storage {
        case .byteBuffer(let buffer):
            bodyDataForSigning = .byteBuffer(buffer)
        case .asyncSequence(let sequence, let length):
            if signer.name == "s3", !serviceConfig.options.contains(.s3DisableChunkedUploads) {
                assert(length != nil, "S3 stream requires size")
                var headers = headers
                // need to add these headers here as it needs to be included in the signed headers
                headers.add(name: "x-amz-decoded-content-length", value: length!.description)
                headers.add(name: "content-encoding", value: "aws-chunked")
                // get signed headers and seed signing data
                let (signedHeaders, seedSigningData) = signer.startSigningChunks(url: self.url, method: self.method, headers: headers, date: Date())
                // create s3 signed Sequence
                let s3Signed = sequence.s3Signed(signer: signer, seedSigningData: seedSigningData)
                // create new payload and return request
                let payload = AWSHTTPBody(asyncSequence: s3Signed, length: s3Signed.contentSize(from: length!))

                self.headers = signedHeaders
                self.body = payload
                return
            } else {
                bodyDataForSigning = .unsignedPayload
            }
        }
        let signedHeaders = signer.signHeaders(url: self.url, method: self.method, headers: self.headers, body: bodyDataForSigning, date: Date())
        self.headers = signedHeaders
    }
}

extension AWSHTTPRequest {
    internal init(operation operationName: String, path: String, method: HTTPMethod, configuration: AWSServiceConfig) throws {
        var headers = HTTPHeaders()

        guard let url = URL(string: "\(configuration.endpoint)\(path)"), let _ = url.host else {
            throw AWSClient.ClientError.invalidURL
        }

        // set x-amz-target header
        if let target = configuration.amzTarget {
            headers.replaceOrAdd(name: "x-amz-target", value: "\(target).\(operationName)")
        }

        self.url = url
        self.method = method
        self.headers = headers
        // Query and EC2 protocols require the Action and API Version in the body
        switch configuration.serviceProtocol {
        case .query, .ec2:
            let params = ["Action": operationName, "Version": configuration.apiVersion]
            if let queryBody = try QueryEncoder().encode(params) {
                self.body = .init(buffer: configuration.byteBufferAllocator.buffer(string: queryBody))
            } else {
                self.body = .init()
            }
        default:
            self.body = .init()
        }

        self.addStandardHeaders(serviceProtocol: configuration.serviceProtocol, raw: false)
    }

    internal init<Input: AWSEncodableShape>(
        operation operationName: String,
        path: String,
        method: HTTPMethod,
        input: Input,
        hostPrefix: String? = nil,
        configuration: AWSServiceConfig
    ) throws {
        // validate input parameters
        try input.validate()

        let requestEncoderContainer = RequestEncodingContainer(path: path, hostPrefix: hostPrefix)

        var body: AWSHTTPBody
        switch configuration.serviceProtocol {
        case .json, .restjson:
            let encoder = JSONEncoder()
            encoder.userInfo[.awsRequest] = requestEncoderContainer
            encoder.dateEncodingStrategy = .secondsSince1970
            let buffer = try encoder.encodeAsByteBuffer(input, allocator: configuration.byteBufferAllocator)
            if method == .GET || method == .HEAD, buffer == ByteBuffer(string: "{}") {
                body = .init()
            } else {
                body = .init(buffer: buffer)
            }

        case .restxml:
            var encoder = XMLEncoder()
            encoder.userInfo[.awsRequest] = requestEncoderContainer
            let xml = try encoder.encode(input, name: Input._xmlRootNodeName)
            if let xml = xml, xml.childCount > 0 {
                if let xmlNamespace = Input._xmlNamespace ?? configuration.xmlNamespace {
                    xml.addNamespace(XML.Node.namespace(stringValue: xmlNamespace))
                }
                let document = XML.Document(rootElement: xml)
                let xmlDocument = document.xmlString
                body = .init(buffer: configuration.byteBufferAllocator.buffer(string: xmlDocument))
            } else {
                body = .init()
            }

        case .query:
            var encoder = QueryEncoder()
            encoder.userInfo[.awsRequest] = requestEncoderContainer
            encoder.additionalKeys = ["Action": operationName, "Version": configuration.apiVersion]
            if let query = try encoder.encode(input) {
                body = .init(buffer: configuration.byteBufferAllocator.buffer(string: query))
            } else {
                body = .init()
            }

        case .ec2:
            var encoder = QueryEncoder()
            encoder.userInfo[.awsRequest] = requestEncoderContainer
            encoder.additionalKeys = ["Action": operationName, "Version": configuration.apiVersion]
            encoder.ec2 = true
            if let query = try encoder.encode(input) {
                body = .init(buffer: configuration.byteBufferAllocator.buffer(string: query))
            } else {
                body = .init()
            }
        }
        body = requestEncoderContainer.body ?? body
        var headers = Self.calculateChecksumHeader(
            headers: requestEncoderContainer.headers,
            body: body,
            shapeType: Input.self,
            configuration: configuration
        )

        // set x-amz-target header
        if let target = configuration.amzTarget {
            headers.replaceOrAdd(name: "x-amz-target", value: "\(target).\(operationName)")
        }

        self.url = try requestEncoderContainer.buildURL(endpoint: configuration.endpoint)
        self.method = method
        self.headers = headers
        self.body = body

        self.addStandardHeaders(serviceProtocol: configuration.serviceProtocol, raw: requestEncoderContainer.body != nil)
    }

    /// Calculate checksum header for request
    /// - Parameters:
    ///   - headers: request headers
    ///   - body: request body
    ///   - shapeType: Request shape type
    ///   - configuration: Service configuration
    /// - Returns: New set of headers
    private static func calculateChecksumHeader<Input: AWSEncodableShape>(
        headers: HTTPHeaders,
        body: AWSHTTPBody,
        shapeType: Input.Type,
        configuration: AWSServiceConfig
    ) -> HTTPHeaders {
        var headers = headers
        var checksumType: ChecksumType?
        if shapeType._options.contains(.checksumHeader) {
            checksumType = headers["x-amz-sdk-checksum-algorithm"].first.map { ChecksumType(rawValue: $0) } ?? nil
        }
        if checksumType == nil {
            if Input._options.contains(.checksumRequired) ||
                (Input._options.contains(.md5ChecksumHeader) && configuration.options.contains(.calculateMD5))
            {
                checksumType = .md5
            }
        }

        guard let checksumType = checksumType,
              case .byteBuffer(let buffer) = body.storage,
              let checksumHeader = Self.checksumHeaders[checksumType],
              headers[checksumHeader].first == nil else { return headers }

        var checksum: String?
        switch checksumType {
        case .crc32:
            let bufferView = ByteBufferView(buffer)
            let crc = soto_crc32(0, bytes: bufferView)
            var crc32 = UInt32(crc).bigEndian
            let data = withUnsafePointer(to: &crc32) { pointer in
                return Data(bytes: pointer, count: 4)
            }
            checksum = data.base64EncodedString()
        case .crc32c:
            let bufferView = ByteBufferView(buffer)
            let crc = soto_crc32c(0, bytes: bufferView)
            var crc32 = UInt32(crc).bigEndian
            let data = withUnsafePointer(to: &crc32) { pointer in
                return Data(bytes: pointer, count: 4)
            }
            checksum = data.base64EncodedString()
        case .sha1:
            checksum = self.calculateChecksum(buffer, function: Insecure.SHA1.self)
        case .sha256:
            checksum = self.calculateChecksum(buffer, function: SHA256.self)
        case .md5:
            checksum = self.calculateChecksum(buffer, function: Insecure.MD5.self)
        }
        if let checksum = checksum {
            headers.add(name: checksumHeader, value: checksum)
        }
        return headers
    }

    /// Add headers standard to all requests "content-type" and "user-agent"
    private mutating func addStandardHeaders(serviceProtocol: ServiceProtocol, raw: Bool) {
        self.headers.add(name: "user-agent", value: "Soto/6.0")
        guard self.headers["content-type"].first == nil else {
            return
        }
        guard self.method != .GET, self.method != .HEAD else {
            return
        }

        if case .byteBuffer(let buffer) = body.storage, buffer.readableBytes == 0 {
            // don't add a content-type header when there is no content
        } else if case .restjson = serviceProtocol, raw {
            self.headers.replaceOrAdd(name: "content-type", value: "binary/octet-stream")
        } else {
            self.headers.replaceOrAdd(name: "content-type", value: serviceProtocol.contentType)
        }
    }

    /// verify  streaming is allowed for this operation
    internal static func verifyStream(operation: String, payload: AWSHTTPBody, input: any AWSEncodableShape.Type) {
        guard case .asyncSequence(_, let length) = payload.storage else { return }
        precondition(input._options.contains(.allowStreaming), "\(operation) does not allow streaming of data")
        precondition(length != nil || input._options.contains(.allowChunkedStreaming), "\(operation) does not allow chunked streaming of data. Please supply a data size.")
    }

    private static func calculateChecksum<H: HashFunction>(_ byteBuffer: ByteBuffer, function: H.Type) -> String? {
        // if request has a body, calculate the MD5 for that body
        let byteBufferView = byteBuffer.readableBytesView
        return byteBufferView.withContiguousStorageIfAvailable { bytes in
            return Data(H.hash(data: bytes)).base64EncodedString()
        }
    }

    private enum ChecksumType: String {
        case crc32 = "CRC32"
        case crc32c = "CRC32C"
        case sha1 = "SHA1"
        case sha256 = "SHA256"
        case md5 = "MD5"
    }

    private static let checksumHeaders: [ChecksumType: String] = [
        .crc32: "x-amz-checksum-crc32",
        .crc32c: "x-amz-checksum-crc32c",
        .sha1: "x-amz-checksum-sha1",
        .sha256: "x-amz-checksum-sha256",
        .md5: "content-md5",
    ]
}

private protocol AWSRequestEncodableArray {
    var encoded: [String] { get }
}

extension Array: AWSRequestEncodableArray {
    var encoded: [String] { return self.map { "\($0)" }}
}

private protocol AWSRequestEncodableDictionary {
    var encoded: [(key: String, value: String)] { get }
}

extension Dictionary: AWSRequestEncodableDictionary {
    var encoded: [(key: String, value: String)] {
        return self.map { (key: "\($0.key)", value: "\($0.value)") }
    }
}

private protocol AWSRequestEncodableString {
    var encoded: String? { get }
}

extension CustomCoding: AWSRequestEncodableString where Coder: CustomEncoder {
    var encoded: String? {
        return Coder.string(from: self.wrappedValue)
    }
}

extension OptionalCustomCoding: AWSRequestEncodableString where Coder: CustomEncoder {
    var encoded: String? {
        guard let value = self.wrappedValue else { return nil }
        return Coder.string(from: value)
    }
}
