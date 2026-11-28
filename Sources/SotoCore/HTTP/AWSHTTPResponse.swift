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

import Algorithms
import AsyncHTTPClient
public import HTTPTypes
import Logging
import NIOCore
import NIOFoundationEssentialsCompat
internal import SotoXML

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif

/// Structure encapsulating an HTTP Response
public struct AWSHTTPResponse: Sendable {
    public let response: HTTPResponse
    /// response body
    public var body: AWSHTTPBody

    /// Response status code
    @inlinable
    public var status: HTTPResponse.Status { self.response.status }

    /// Response headers
    @inlinable
    public var headers: HTTPFields { self.response.headerFields }

    /// Initialize AWSResponse
    @inlinable
    public init(response: HTTPResponse, body: AWSHTTPBody = .init()) {
        self.response = response
        self.body = body
    }

    mutating func collateBody() async throws {
        self.body = try await .init(buffer: self.body.collect(upTo: .max))
    }

    /// Generate AWSShape from AWSResponse
    func generateOutputShape<Output: AWSDecodableShape>(operation: String, serviceProtocol: ServiceProtocol) throws -> Output {
        var payload: ByteBuffer? = nil
        if case .byteBuffer(let buffer) = self.body.storage, !Output._options.contains(.rawPayload) {
            payload = buffer
        }

        return try AWSCodingContext.$response.withValue(ResponseDecodingContainer(response: self, serviceProtocol: serviceProtocol)) {
            switch serviceProtocol {
            case .json, .restjson:
                let payloadData: Data
                if let payload, payload.readableBytes > 0 {
                    payloadData = Data(buffer: payload, byteTransferStrategy: .noCopy)
                } else {
                    payloadData = Data("{}".utf8)
                }
                let jsonDecoder = JSONDecoder()
                jsonDecoder.dateDecodingStrategy = .secondsSince1970
                return try jsonDecoder.decode(Output.self, from: payloadData)

            case .rpcv2Cbor:
                return try RPCv2CBOR.decode(Output.self, from: payload)

            case .restxml, .query, .ec2:
                var xmlElement: XML.Element
                if let buffer = payload,
                    let xmlDocument = try? XML.Document(buffer: buffer),
                    let rootElement = xmlDocument.rootElement()
                {
                    xmlElement = rootElement
                    // if root element is called operation name + "Response" and its child is called
                    // operation name + "Result" then use the child as the root element when decoding
                    // XML
                    if let child = xmlElement.children(of: .element)?.first as? XML.Element,
                        xmlElement.name == operation + "Response",
                        child.name == operation + "Result"
                    {
                        xmlElement = child
                    }
                } else {
                    xmlElement = .init(name: "__empty_element")
                }
                return try XMLDecoder().decode(Output.self, from: xmlElement)
            }
        }
    }

    /// extract error code and message from AWSResponse
    func generateError(serviceConfig: AWSServiceConfig, logLevel: Logger.Level = .info, logger: Logger) -> (any AWSErrorType)? {
        do {
            let errorType = serviceConfig.errorType ?? AWSResponseError.self
            if let serviceError = try self.decodeAWSError(as: errorType, serviceConfig: serviceConfig) {
                logger.log(
                    level: logLevel,
                    "AWS Error",
                    metadata: [
                        "aws-error-code": .string(serviceError.errorCode),
                        "aws-error-message": .string(serviceError.message ?? ""),
                    ]
                )
                return serviceError
            }
        } catch let error as AWSResponseError {
            logger.log(
                level: logLevel,
                "AWS Error",
                metadata: [
                    "aws-error-code": .string(error.errorCode),
                    "aws-error-message": .string(error.message ?? ""),
                ]
            )
            // we have an error that isn't recognised by the service but we have an errorCode. Some services but not all
            // append all errors with the word "Exception". To get consistent standard errors we remove this from the error
            // code
            if error.errorCode.hasSuffix("Exception") {
                let errorCode = String(error.errorCode.dropLast(9))
                let newError = AWSResponseError(errorCode: errorCode, message: error.message, response: error.response)
                return newError
            }
            return error
        } catch {
            return nil
        }
        return nil
    }

    /// extract error code and message from AWSResponse
    fileprivate func decodeAWSError<AWSError: Decodable>(as: AWSError.Type, serviceConfig: AWSServiceConfig) throws -> AWSError? {
        switch self.body.storage {
        case .asyncSequence:
            return nil

        case .byteBuffer(let buffer):
            return try AWSCodingContext.$response.withValue(
                ResponseDecodingContainer(response: self, serviceProtocol: serviceConfig.serviceProtocol)
            ) {
                switch serviceConfig.serviceProtocol {
                case .restjson, .json:
                    return try JSONDecoder().decode(AWSError.self, from: buffer)

                case .rpcv2Cbor:
                    return try RPCv2CBOR.decode(AWSError.self, from: buffer)

                case .restxml:
                    let xmlDocument = try XML.Document(buffer: buffer)
                    guard var element = xmlDocument.rootElement() else { return nil }
                    if let error = element.elements(forName: "Error").first {
                        element = error
                    }
                    return try XMLDecoder().decode(AWSError.self, from: element)

                case .query:
                    let xmlDocument = try XML.Document(buffer: buffer)
                    guard let element = xmlDocument.rootElement() else { return nil }
                    guard let errorElement = element.elements(forName: "Error").first else { return nil }
                    return try XMLDecoder().decode(AWSError.self, from: errorElement)

                case .ec2:
                    let xmlDocument = try XML.Document(buffer: buffer)
                    guard var element = xmlDocument.rootElement() else { return nil }
                    if let errors = element.elements(forName: "Errors").first {
                        element = errors
                    }
                    guard let errorElement = element.elements(forName: "Error").first else { return nil }
                    return try XMLDecoder().decode(AWSError.self, from: errorElement)
                }
            }
        }
    }
}

extension XML.Document {
    internal convenience init(buffer: ByteBuffer) throws {
        let xmlString = String(buffer: buffer)
        try self.init(string: xmlString)
    }
}
