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

import AsyncHTTPClient
import Logging
import NIOCore
import NIOFoundationCompat
import NIOHTTP1
internal import SotoXML

import struct Foundation.Data
import struct Foundation.Date
import class Foundation.DateFormatter
import class Foundation.JSONDecoder
import class Foundation.JSONSerialization
import struct Foundation.Locale
import struct Foundation.TimeZone

/// Structure encapsulating an HTTP Response
public struct AWSHTTPResponse: Sendable {
    /// response status
    public let status: HTTPResponseStatus
    /// response headers
    public var headers: HTTPHeaders
    /// response body
    public var body: AWSHTTPBody

    /// Initialize AWSResponse
    init(status: HTTPResponseStatus, headers: HTTPHeaders, body: AWSHTTPBody = .init()) {
        self.status = status
        self.headers = headers
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
            if self.isHypertextApplicationLanguage {
                payloadData = try self.getHypertextApplicationLanguageDictionary()
            } else if let payload, payload.readableBytes > 0 {
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
    func generateError(serviceConfig: AWSServiceConfig, logLevel: Logger.Level = .info, logger: Logger) -> Error? {
        var apiError: APIError?
        switch self.body.storage {
        case .asyncSequence:
            break

        case .byteBuffer(let buffer):
            switch serviceConfig.serviceProtocol {
            case .restjson:
                let jsonDecoder = JSONDecoder()
                jsonDecoder.userInfo[.awsErrorMap] = serviceConfig.errorType
                apiError = try? jsonDecoder.decode(RESTJSONError.self, from: buffer)
                if apiError?.code == nil {
                    apiError?.code = self.headers["x-amzn-errortype"].first
                }

            case .json:
                let jsonDecoder = JSONDecoder()
                jsonDecoder.userInfo[.awsErrorMap] = serviceConfig.errorType
                apiError = try? jsonDecoder.decode(JSONError.self, from: buffer)

            case .query:
                let xmlDocument = try? XML.Document(buffer: buffer)
                guard var element = xmlDocument?.rootElement() else { break }
                if let errors = element.elements(forName: "Errors").first {
                    element = errors
                }
                guard let errorElement = element.elements(forName: "Error").first else { break }
                var xmlDecoder = XMLDecoder()
                xmlDecoder.userInfo[.awsErrorMap] = serviceConfig.errorType
                apiError = try? xmlDecoder.decode(XMLQueryError.self, from: errorElement)

            case .restxml:
                let xmlDocument = try? XML.Document(buffer: buffer)
                guard var element = xmlDocument?.rootElement() else { break }
                if let error = element.elements(forName: "Error").first {
                    element = error
                }
                var xmlDecoder = XMLDecoder()
                xmlDecoder.userInfo[.awsErrorMap] = serviceConfig.errorType
                apiError = try? xmlDecoder.decode(XMLQueryError.self, from: element)

            case .ec2:
                let xmlDocument = try? XML.Document(buffer: buffer)
                guard var element = xmlDocument?.rootElement() else { break }
                if let errors = element.elements(forName: "Errors").first {
                    element = errors
                }
                guard let errorElement = element.elements(forName: "Error").first else { break }
                var xmlDecoder = XMLDecoder()
                xmlDecoder.userInfo[.awsErrorMap] = serviceConfig.errorType
                apiError = try? xmlDecoder.decode(XMLQueryError.self, from: errorElement)
            }
        }
        if let errorMessage = apiError, var code = errorMessage.code {
            // remove code prefix before #
            if let index = code.firstIndex(of: "#") {
                code = String(code[code.index(index, offsetBy: 1)...])
            }

            logger.log(
                level: logLevel,
                "AWS Error",
                metadata: [
                    "aws-error-code": .string(code),
                    "aws-error-message": .string(errorMessage.message),
                ]
            )

            let context = AWSErrorContext(
                message: errorMessage.message,
                responseCode: self.status,
                headers: self.headers,
                additionalFields: errorMessage.additionalFields,
                extendedError: errorMessage.extendedError
            )

            if let errorType = serviceConfig.errorType {
                if let error = errorType.init(errorCode: code, context: context) {
                    return error
                }
            }
            if let error = AWSClientError(errorCode: code, context: context) {
                return error
            }

            if let error = AWSServerError(errorCode: code, context: context) {
                return error
            }

            return AWSResponseError(errorCode: code, context: context)
        }

        return nil
    }

    /// Error used by XML output
    private struct XMLQueryError: Decodable, APIError {
        var code: String?
        let message: String
        let additionalFields: [String: String]
        let extendedError: AWSErrorShape?

        init(from decoder: Decoder) throws {
            // use `ErrorCodingKey` so we get extract additional keys from `container.allKeys`
            let container = try decoder.container(keyedBy: ErrorCodingKey.self)
            let code = try container.decodeIfPresent(String.self, forKey: .init("Code"))
            // Remove namespace from error code
            self.code = code?.split(separator: "#").last.map { String($0) }
            self.message = try container.decode(String.self, forKey: .init("Message"))

            if let code = self.code,
                let errorMapping = decoder.userInfo[.awsErrorMap] as? AWSServiceErrorType.Type,
                let errorType = errorMapping.errorCodeMap[code]
            {
                let container = try decoder.singleValueContainer()
                self.extendedError = try? container.decode(errorType)
            } else {
                self.extendedError = nil
            }

            var additionalFields: [String: String] = [:]
            for key in container.allKeys {
                guard key.stringValue != "Code", key.stringValue != "Message" else { continue }
                do {
                    additionalFields[key.stringValue] = try container.decodeIfPresent(String.self, forKey: key)
                } catch {}
            }
            self.additionalFields = additionalFields
        }
    }

    private struct JSONError: Decodable, APIError {
        var code: String?
        let message: String
        let additionalFields: [String: String]
        let extendedError: AWSErrorShape?

        init(from decoder: Decoder) throws {
            // use `ErrorCodingKey` so we get extract additional keys from `container.allKeys`
            let container = try decoder.container(keyedBy: ErrorCodingKey.self)
            let code = try container.decodeIfPresent(String.self, forKey: .init("__type"))
            // Remove namespace from error code
            self.code = code?.split(separator: "#").last.map { String($0) }
            self.message =
                try container.decodeIfPresent(String.self, forKey: .init("message")) ?? container.decode(String.self, forKey: .init("Message"))

            let errorMapping = decoder.userInfo[.awsErrorMap]
            if let code = self.code,
                let errorMapping = errorMapping as? AWSServiceErrorType.Type,
                let errorType = errorMapping.errorCodeMap[code]
            {
                let container = try decoder.singleValueContainer()
                self.extendedError = try? container.decode(errorType)
            } else {
                self.extendedError = nil
            }
            var additionalFields: [String: String] = [:]
            for key in container.allKeys {
                guard key.stringValue != "__type", key.stringValue != "message", key.stringValue != "Message" else { continue }
                do {
                    additionalFields[key.stringValue] = try container.decodeIfPresent(String.self, forKey: key)
                } catch {}
            }
            self.additionalFields = additionalFields
        }
    }

    /// Error used by REST JSON output
    private struct RESTJSONError: Decodable, APIError {
        var code: String?
        let message: String
        let additionalFields: [String: String]
        let extendedError: AWSErrorShape?

        init(from decoder: Decoder) throws {
            // use `ErrorCodingKey` so we get extract additional keys from `container.allKeys`
            let container = try decoder.container(keyedBy: ErrorCodingKey.self)
            let code = try container.decodeIfPresent(String.self, forKey: .init("code"))
            // Remove namespace from error code
            self.code = code?.split(separator: "#").last.map { String($0) }
            self.message =
                try container.decodeIfPresent(String.self, forKey: .init("message")) ?? container.decode(String.self, forKey: .init("Message"))

            if let code = self.code,
                let errorMapping = decoder.userInfo[.awsErrorMap] as? AWSServiceErrorType.Type,
                let errorType = errorMapping.errorCodeMap[code]
            {
                let container = try decoder.singleValueContainer()
                self.extendedError = try? container.decode(errorType)
            } else {
                self.extendedError = nil
            }

            var additionalFields: [String: String] = [:]
            for key in container.allKeys {
                guard key.stringValue != "code", key.stringValue != "message", key.stringValue != "Message" else { continue }
                do {
                    additionalFields[key.stringValue] = try container.decodeIfPresent(String.self, forKey: key)
                } catch {}
            }
            self.additionalFields = additionalFields
        }
    }

    /// CodingKey used when decoding Errors
    private struct ErrorCodingKey: CodingKey {
        var stringValue: String
        var intValue: Int?

        init(_ stringValue: String) {
            self.stringValue = stringValue
            self.intValue = nil
        }

        init?(stringValue: String) {
            self.stringValue = stringValue
            self.intValue = nil
        }

        init?(intValue: Int) {
            return nil
        }
    }
}

private protocol APIError {
    var code: String? { get set }
    var message: String { get }
    var additionalFields: [String: String] { get }
    var extendedError: AWSErrorShape? { get }
}

extension XML.Document {
    internal convenience init(buffer: ByteBuffer) throws {
        let xmlString = String(buffer: buffer)
        try self.init(string: xmlString)
    }
}

extension CodingUserInfoKey {
    public static var awsErrorMap: Self { .init(rawValue: "soto.awsErrorMap")! }
}
