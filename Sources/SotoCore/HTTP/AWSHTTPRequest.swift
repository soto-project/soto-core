//===----------------------------------------------------------------------===//
//
// This source file is part of the Soto for AWS open source project
//
// Copyright (c) 2017-2026 the Soto project authors
// Licensed under Apache License v2.0
//
// See LICENSE.txt for license information
// See CONTRIBUTORS.txt for the list of Soto project authors
//
// SPDX-License-Identifier: Apache-2.0
//
//===----------------------------------------------------------------------===//

import Crypto
public import HTTPTypes
import NIOCore
import NIOFoundationEssentialsCompat
import SotoSignerV4
internal import SotoXML

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif

/// Object encapsulating all the information needed to generate a raw HTTP request to AWS
public struct AWSHTTPRequest: Sendable {
    public var request: HTTPRequest
    /// request body
    public var body: AWSHTTPBody

    public init(request: HTTPRequest, body: AWSHTTPBody = .init()) {
        self.request = request
        self.body = body
    }

    /// HTTP Request method
    @inlinable
    public var method: HTTPRequest.Method { self.request.method }

    /// HTTP Request headers
    @inlinable
    public var headers: HTTPFields { self.request.headerFields }

    /// Create signed headers for request
    mutating func signHeaders(signer: AWSSigner, serviceConfig: AWSServiceConfig) {
        guard !signer.credentials.isEmpty() else { return }
        let payload = self.body
        switch payload.storage {
        case .byteBuffer(let buffer):
            signer.signHeaders(request: &request, body: buffer.readableBytesSpan, date: Date.now)
        case .asyncSequence(let sequence, let length):
            if signer.name == "s3", !serviceConfig.options.contains(.s3DisableChunkedUploads) {
                assert(length != nil, "S3 stream requires size")
                // need to add these headers here as it needs to be included in the signed headers
                self.request.headerFields[.xAmzDecodedContentLength] = length!.description
                self.request.headerFields[.contentEncoding] = "aws-chunked"
                // get signed headers and seed signing data
                let seedSigningData = signer.startSigningChunks(request: &self.request, date: Date())!
                // create s3 signed Sequence
                let s3Signed = sequence.s3Signed(signer: signer, seedSigningData: seedSigningData)
                // create new payload and return request
                let payload = AWSHTTPBody(asyncSequence: s3Signed, length: s3Signed.contentSize(from: length!))

                self.body = payload
                return
            } else {
                signer.signHeaders(request: &self.request, payload: .unsignedPayload, date: Date())
            }
        }

    }
}

extension AWSHTTPRequest {
    internal init(operation operationName: String, path: String, method: HTTPRequest.Method, configuration: AWSServiceConfig) throws {
        var headers = HTTPFields()

        guard let url = URL(string: "\(configuration.endpoint)\(path)"), let _ = url.host else {
            throw AWSClient.ClientError.invalidURL
        }

        // set x-amz-target header
        if let target = configuration.amzTarget {
            headers[.xAmzTarget] = "\(target).\(operationName)"
        }

        self.request = HTTPRequest(method: method, url: url, headerFields: headers)
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
        method: HTTPRequest.Method,
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
            // GET, HEAD and DELETE methods should have an empty body
            if method == .get || method == .head || method == .delete, buffer == ByteBuffer(string: "{}") {
                body = .init()
            } else {
                body = .init(buffer: buffer)
            }

        case .restxml:
            var encoder = XMLEncoder()
            encoder.userInfo[.awsRequest] = requestEncoderContainer
            let xml = try encoder.encode(input, name: Input._xmlRootNodeName)
            if let xml, xml.childCount > 0 {
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
        Self.calculateChecksumHeader(
            headers: &requestEncoderContainer.headers,
            body: body,
            shapeType: Input.self,
            configuration: configuration
        )

        // set x-amz-target header
        if let target = configuration.amzTarget {
            requestEncoderContainer.headers[.xAmzTarget] = "\(target).\(operationName)"
        }

        self.request = HTTPRequest(
            method: method,
            url: try requestEncoderContainer.buildURL(endpoint: configuration.endpoint),
            headerFields: requestEncoderContainer.headers
        )
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
        headers: inout HTTPFields,
        body: AWSHTTPBody,
        shapeType: Input.Type,
        configuration: AWSServiceConfig
    ) {
        var checksumType: ChecksumType?
        if shapeType._options.contains(.checksumHeader) {
            checksumType = headers[.xAmzSdkChecksumAlgorithm].map { ChecksumType(rawValue: $0) } ?? nil
        }
        if checksumType == nil {
            if Input._options.contains(.checksumRequired)
                || (Input._options.contains(.md5ChecksumHeader) && configuration.options.contains(.calculateMD5))
            {
                checksumType = .defaultMD5
            }
        }

        guard let checksumType,
            case .byteBuffer(let buffer) = body.storage,
            let checksumHeader = Self.checksumHeaders[checksumType],
            headers[checksumHeader] == nil
        else { return }

        var checksum: String?
        switch checksumType {
        case .crc32:
            let bufferView = ByteBufferView(buffer)
            let crc = soto_crc32(0, bytes: bufferView)
            var crc32 = UInt32(crc).bigEndian
            let data = withUnsafePointer(to: &crc32) { pointer in
                Data(bytes: pointer, count: 4)
            }
            checksum = data.base64EncodedString()
        case .crc32c:
            let bufferView = ByteBufferView(buffer)
            let crc = soto_crc32c(0, bytes: bufferView)
            var crc32 = UInt32(crc).bigEndian
            let data = withUnsafePointer(to: &crc32) { pointer in
                Data(bytes: pointer, count: 4)
            }
            checksum = data.base64EncodedString()
        case .sha1:
            checksum = self.calculateChecksum(buffer, function: Insecure.SHA1.self)
        case .sha256:
            checksum = self.calculateChecksum(buffer, function: SHA256.self)
        case .sha512:
            checksum = self.calculateChecksum(buffer, function: SHA512.self)
        case .md5, .defaultMD5:
            checksum = self.calculateChecksum(buffer, function: Insecure.MD5.self)
        }
        if let checksum {
            headers[checksumHeader] = checksum
        }
    }

    /// Add headers standard to all requests "content-type" and "user-agent"
    private mutating func addStandardHeaders(serviceProtocol: ServiceProtocol, raw: Bool) {
        self.request.headerFields[.userAgent] = "Soto/8.0"
        guard self.request.headerFields[.contentType] == nil else {
            return
        }
        // in theory we don't need this check as the check for an empty body should skip adding
        // a header and a GET or HEAD request should have an empty body
        guard self.request.method != .get, self.request.method != .head else {
            return
        }

        if case .byteBuffer(let buffer) = body.storage, buffer.readableBytes == 0 {
            // don't add a content-type header when there is no content
        } else if case .restjson = serviceProtocol, raw {
            self.request.headerFields[.contentType] = "binary/octet-stream"
        } else {
            self.request.headerFields[.contentType] = serviceProtocol.contentType
        }
    }

    /// verify  streaming is allowed for this operation
    internal static func verifyStream(operation: String, payload: AWSHTTPBody, input: any AWSEncodableShape.Type) {
        guard case .asyncSequence(_, let length) = payload.storage else { return }
        precondition(input._options.contains(.allowStreaming), "\(operation) does not allow streaming of data")
        precondition(
            length != nil || input._options.contains(.allowChunkedStreaming),
            "\(operation) does not allow chunked streaming of data. Please supply a data size."
        )
    }

    private static func calculateChecksum<H: HashFunction>(_ byteBuffer: ByteBuffer, function: H.Type) -> String? {
        // if request has a body, calculate the MD5 for that body
        let byteBufferView = byteBuffer.readableBytesView
        return byteBufferView.withContiguousStorageIfAvailable { bytes in
            Data(H.hash(data: bytes)).base64EncodedString()
        }
    }

    private enum ChecksumType: String {
        case crc32 = "CRC32"
        case crc32c = "CRC32C"
        case sha1 = "SHA1"
        case sha256 = "SHA256"
        case sha512 = "SHA512"
        case md5 = "MD5"
        case defaultMD5 = "_default_md5_"
    }

    // TODO: this should really be defined in the shape files but so far we only have S3 using checksums and
    // these are it defined headers
    private static let checksumHeaders: [ChecksumType: HTTPField.Name] = [
        .crc32: .init("x-amz-checksum-crc32")!,
        .crc32c: .init("x-amz-checksum-crc32c")!,
        .sha1: .init("x-amz-checksum-sha1")!,
        .sha256: .init("x-amz-checksum-sha256")!,
        .sha512: .init("x-amz-checksum-sha512")!,
        .md5: .init("x-amz-checksum-md5")!,
        // default to content-md5 header if no algorithm header is found and a checksum is required
        .defaultMD5: .init("content-md5")!,
    ]
}

private protocol AWSRequestEncodableArray {
    var encoded: [String] { get }
}

extension Array: AWSRequestEncodableArray {
    var encoded: [String] { self.map { "\($0)" } }
}

private protocol AWSRequestEncodableDictionary {
    var encoded: [(key: String, value: String)] { get }
}

extension Dictionary: AWSRequestEncodableDictionary {
    var encoded: [(key: String, value: String)] {
        self.map { (key: "\($0.key)", value: "\($0.value)") }
    }
}

private protocol AWSRequestEncodableString {
    var encoded: String? { get }
}

extension CustomCoding: AWSRequestEncodableString where Coder: CustomEncoder {
    var encoded: String? {
        Coder.string(from: self.wrappedValue)
    }
}

extension OptionalCustomCoding: AWSRequestEncodableString where Coder: CustomEncoder {
    var encoded: String? {
        guard let value = self.wrappedValue else { return nil }
        return Coder.string(from: value)
    }
}
