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
        if case .byteBuffer(let buffer) = self.body.storage {
            payload = buffer
        }

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
            jsonDecoder.userInfo[.awsResponse] = ResponseDecodingContainer(response: self)
            return try jsonDecoder.decode(Output.self, from: payloadData)

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
            var xmlDecoder = XMLDecoder()
            xmlDecoder.userInfo[.awsResponse] = ResponseDecodingContainer(response: self)
            return try xmlDecoder.decode(Output.self, from: xmlElement)
        }
    }

    /// extract error code and message from AWSResponse
    func generateError(serviceConfig: AWSServiceConfig, logLevel: Logger.Level = .info, logger: Logger) -> (any Error)? {
        if let serviceErrorType = serviceConfig.errorType,
            let serviceError = self.decodeAWSError(as: serviceErrorType, serviceConfig: serviceConfig)
        {
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
        if let error = self.decodeAWSError(as: AWSResponseError.self, serviceConfig: serviceConfig) {
            logger.log(
                level: logLevel,
                "AWS Error",
                metadata: [
                    "aws-error-code": .string(error.errorCode),
                    "aws-error-message": .string(error.message ?? ""),
                ]
            )
            return error
        }
        return nil
    }

    /// extract error code and message from AWSResponse
    fileprivate func decodeAWSError<AWSError: Decodable>(as: AWSError.Type, serviceConfig: AWSServiceConfig) -> AWSError? {
        switch self.body.storage {
        case .asyncSequence:
            return nil

        case .byteBuffer(let buffer):
            switch serviceConfig.serviceProtocol {
            case .restjson, .json:
                let jsonDecoder = JSONDecoder()
                jsonDecoder.userInfo[.awsErrorMap] = serviceConfig.errorType
                jsonDecoder.userInfo[.awsResponse] = ResponseDecodingContainer(response: self)
                jsonDecoder.userInfo[.awsProtocol] = serviceConfig.serviceProtocol
                return try? jsonDecoder.decode(AWSError.self, from: buffer)

            case .restxml:
                let xmlDocument = try? XML.Document(buffer: buffer)
                guard var element = xmlDocument?.rootElement() else { break }
                if let error = element.elements(forName: "Error").first {
                    element = error
                }
                var xmlDecoder = XMLDecoder()
                xmlDecoder.userInfo[.awsErrorMap] = serviceConfig.errorType
                xmlDecoder.userInfo[.awsResponse] = ResponseDecodingContainer(response: self)
                xmlDecoder.userInfo[.awsProtocol] = serviceConfig.serviceProtocol
                return try? xmlDecoder.decode(AWSError.self, from: element)

            case .query:
                let xmlDocument = try? XML.Document(buffer: buffer)
                guard let element = xmlDocument?.rootElement() else { break }
                guard let errorElement = element.elements(forName: "Error").first else { break }
                var xmlDecoder = XMLDecoder()
                xmlDecoder.userInfo[.awsErrorMap] = serviceConfig.errorType
                xmlDecoder.userInfo[.awsResponse] = ResponseDecodingContainer(response: self)
                xmlDecoder.userInfo[.awsProtocol] = serviceConfig.serviceProtocol
                return try? xmlDecoder.decode(AWSError.self, from: errorElement)

            case .ec2:
                let xmlDocument = try? XML.Document(buffer: buffer)
                guard var element = xmlDocument?.rootElement() else { break }
                if let errors = element.elements(forName: "Errors").first {
                    element = errors
                }
                guard let errorElement = element.elements(forName: "Error").first else { break }
                var xmlDecoder = XMLDecoder()
                xmlDecoder.userInfo[.awsErrorMap] = serviceConfig.errorType
                xmlDecoder.userInfo[.awsResponse] = ResponseDecodingContainer(response: self)
                xmlDecoder.userInfo[.awsProtocol] = serviceConfig.serviceProtocol
                return try? xmlDecoder.decode(AWSError.self, from: errorElement)
            }
        }
        return nil
    }

    struct AWSBaseError: Decodable {
        let code: String
        let message: String?

        init(from decoder: any Decoder) throws {
            let singleValueContainer = try decoder.singleValueContainer()
            let errorCode = try singleValueContainer.decode(AWSErrorCode.self)
            self.code = errorCode.code
            let errorMessage = try singleValueContainer.decode(AWSErrorMessage.self)
            self.message = errorMessage.message
        }

        private enum CodingKeys: String, CodingKey {
            case Message = "Message"
            case message = "message"
        }
    }
}

public struct AWSErrorCode: Decodable {
    public let code: String

    public init(from decoder: any Decoder) throws {
        let serviceProtocol = decoder.userInfo[.awsProtocol]! as! ServiceProtocol
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch serviceProtocol {
        case .restjson, .json:
            let response = decoder.userInfo[.awsResponse]! as! ResponseDecodingContainer
            let code =
                try response.decodeHeaderIfPresent(key: HTTPField.Name.xAmznErrorType.canonicalName)
                ?? container.decodeIfPresent(String.self, forKey: .type)
                ?? container.decode(String.self, forKey: .code)
            let filteredCode = code.suffix { $0 != "#" }.prefix { $0 != ":" }
            self.code = .init(filteredCode)

        case .restxml, .query, .ec2:
            self.code = try container.decode(String.self, forKey: .Code)
        }
    }

    private enum CodingKeys: String, CodingKey {
        case Code = "Code"
        case type = "__type"
        case code = "code"
    }
}

public struct AWSErrorMessage: Decodable {
    public let message: String?

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.message = try container.decodeIfPresent(String.self, forKey: .Message) ?? container.decodeIfPresent(String.self, forKey: .message)
    }

    private enum CodingKeys: String, CodingKey {
        case Message = "Message"
        case message = "message"
    }
}

extension XML.Document {
    internal convenience init(buffer: ByteBuffer) throws {
        let xmlString = String(buffer: buffer)
        try self.init(string: xmlString)
    }
}

extension CodingUserInfoKey {
    public static var awsErrorMap: Self { .init(rawValue: "soto.awsErrorMap")! }
    public static var awsProtocol: Self { .init(rawValue: "soto.awsProtocol")! }
}
