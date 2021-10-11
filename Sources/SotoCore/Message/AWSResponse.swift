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

import class Foundation.JSONDecoder
import class Foundation.JSONSerialization
import Logging
import NIOCore
import NIOHTTP1
import SotoXML

/// Structure encapsulating a processed HTTP Response
public struct AWSResponse {
    /// response status
    public let status: HTTPResponseStatus
    /// response headers
    public var headers: HTTPHeaders
    /// response body
    public var body: Body

    /// initialize an AWSResponse Object
    /// - parameters:
    ///     - from: Raw HTTP Response
    ///     - serviceProtocol: protocol of service (.json, .xml, .query etc)
    ///     - raw: Whether Body should be treated as raw data
    init(from response: AWSHTTPResponse, serviceProtocol: ServiceProtocol, raw: Bool = false) throws {
        self.status = response.status

        // headers
        self.headers = response.headers

        // body
        guard let body = response.body,
              body.readableBytes > 0
        else {
            self.body = .empty
            return
        }

        if raw {
            self.body = .raw(.byteBuffer(body))
            return
        }

        if body.readableBytes == 0 {
            self.body = .empty
            return
        }

        var responseBody: Body = .empty

        switch serviceProtocol {
        case .json, .restjson:
            responseBody = .json(body)

        case .restxml, .query, .ec2:
            if let xmlString = body.getString(at: body.readerIndex, length: body.readableBytes) {
                let xmlDocument = try XML.Document(string: xmlString)
                if let element = xmlDocument.rootElement() {
                    responseBody = .xml(element)
                }
            }
        }
        self.body = responseBody
    }

    /// return new response with middleware applied
    func applyMiddlewares(_ middlewares: [AWSServiceMiddleware], config: AWSServiceConfig) throws -> AWSResponse {
        var awsResponse = self
        // apply middleware to respons
        let context = AWSMiddlewareContext(options: config.options)
        for middleware in middlewares {
            awsResponse = try middleware.chain(response: awsResponse, context: context)
        }
        return awsResponse
    }

    /// Generate AWSShape from AWSResponse
    func generateOutputShape<Output: AWSDecodableShape>(operation: String) throws -> Output {
        var payloadKey: String? = (Output.self as? AWSShapeWithPayload.Type)?._payloadPath

        // if response has a payload with encoding info
        if let payloadPath = payloadKey, let encoding = Output.getEncoding(for: payloadPath) {
            // get CodingKey string for payload to insert in output
            if let location = encoding.location, case .body(let name) = location {
                payloadKey = name
            }
        }
        let decoder = DictionaryDecoder()

        var outputDict: [String: Any] = [:]
        switch body {
        case .json(let buffer):
            if let data = buffer.getData(at: buffer.readerIndex, length: buffer.readableBytes, byteTransferStrategy: .noCopy) {
                // if required apply hypertext application language transform to body
                if self.isHypertextApplicationLanguage {
                    outputDict = try self.getHypertextApplicationLanguageDictionary()
                } else {
                    outputDict = try JSONSerialization.jsonObject(with: data, options: []) as? [String: Any] ?? [:]
                }
                // if payload path is set then the decode will expect the payload to decode to the relevant member variable
                if let payloadKey = payloadKey {
                    outputDict = [payloadKey: outputDict]
                }
                decoder.dateDecodingStrategy = .secondsSince1970
            }
        case .xml(let node):
            var outputNode = node
            // if payload path is set then the decode will expect the payload to decode to the relevant member variable.
            // Most CloudFront responses have this.
            if let payloadKey = payloadKey {
                // set output node name
                outputNode.name = payloadKey
                // create parent node and add output node and set output node to parent
                let parentNode = XML.Element(name: "Container")
                parentNode.addChild(outputNode)
                outputNode = parentNode
            } else if let child = node.children(of: .element)?.first as? XML.Element,
                      node.name == operation + "Response",
                      child.name == operation + "Result"
            {
                outputNode = child
            }

            // add headers to XML
            addHeadersToXML(rootElement: outputNode, output: Output.self)

            // add status code to XML
            if let statusCodeParam = Output.statusCodeParam {
                let node = XML.Element(name: statusCodeParam, stringValue: "\(self.status.code)")
                outputNode.addChild(node)
            }
            return try XMLDecoder().decode(Output.self, from: outputNode)

        case .raw(let payload):
            if let payloadKey = payloadKey {
                outputDict[payloadKey] = payload
            }
            // if body is raw or empty then assume any date to be decoded will be coming from headers
            decoder.dateDecodingStrategy = .formatted(HTTPHeaderDateCoder.dateFormatters.first!)

        default:
            decoder.dateDecodingStrategy = .formatted(HTTPHeaderDateCoder.dateFormatters.first!)
        }

        // add headers to output dictionary
        outputDict = addHeadersToDictionary(dictionary: outputDict, output: Output.self)

        // add status code to output dictionary
        if let statusCodeParam = Output.statusCodeParam {
            outputDict[statusCodeParam] = self.status.code
        }

        return try decoder.decode(Output.self, from: outputDict)
    }

    /// Add headers required by Output type found in the response into dictionary to be decoded by Dictionary decoder
    private func addHeadersToDictionary<Output: AWSDecodableShape>(dictionary: [String: Any], output: Output.Type) -> [String: Any] {
        var dictionary = dictionary
        // add header values to output dictionary, so they can be decoded into the response object
        for (key, value) in self.headers {
            let headerParams = Output.headerParams
            if let index = headerParams.firstIndex(where: { $0.key.lowercased() == key.lowercased() }) {
                dictionary[headerParams[index].key] = HTTPHeaderDecodable(value)
            }
        }
        for param in Output.headerPrefixParams {
            var valuesDict: [String: Any] = [:]
            for (key, value) in self.headers {
                guard key.lowercased().hasPrefix(param.key.lowercased()) else { continue }
                let shortKey = String(key.dropFirst(param.key.count))
                valuesDict[shortKey] = HTTPHeaderDecodable(value)
            }
            if valuesDict.count > 0 {
                dictionary[param.key] = valuesDict
            }
        }
        return dictionary
    }

    /// Add headers required by Output type found in the response into xml to be decoded by xml decoder
    private func addHeadersToXML<Output: AWSDecodableShape>(rootElement: XML.Element, output: Output.Type) {
        // add header values to xmlnode as children nodes, so they can be decoded into the response object
        for (key, value) in self.headers {
            let headerParams = Output.headerParams
            if let index = headerParams.firstIndex(where: { $0.key.lowercased() == key.lowercased() }) {
                let node = XML.Element(name: headerParams[index].key, stringValue: value)
                rootElement.addChild(node)
            }
        }
        for param in Output.headerPrefixParams {
            let parentNode = XML.Element(name: param.key)
            rootElement.addChild(parentNode)
            for (key, value) in self.headers {
                guard key.hasPrefix(param.key) else { continue }
                let entryNode = XML.Element(name: String(key.dropFirst(param.key.count)), stringValue: value)
                parentNode.addChild(entryNode)
            }
        }
    }

    /// extract error code and message from AWSResponse
    func generateError(serviceConfig: AWSServiceConfig, logLevel: Logger.Level = .info, logger: Logger) -> Error? {
        var apiError: APIError?
        switch serviceConfig.serviceProtocol {
        case .restjson:
            guard case .json(let data) = self.body else { break }
            apiError = try? JSONDecoder().decode(RESTJSONError.self, from: data)
            if apiError?.code == nil {
                apiError?.code = self.headers["x-amzn-errortype"].first
            }

        case .json:
            guard case .json(let data) = self.body else { break }
            apiError = try? JSONDecoder().decode(JSONError.self, from: data)

        case .query:
            guard case .xml(var element) = self.body else { break }
            if let errors = element.elements(forName: "Errors").first {
                element = errors
            }
            guard let errorElement = element.elements(forName: "Error").first else { break }
            apiError = try? XMLDecoder().decode(XMLQueryError.self, from: errorElement)

        case .restxml:
            guard case .xml(var element) = self.body else { break }
            if let error = element.elements(forName: "Error").first {
                element = error
            }
            apiError = try? XMLDecoder().decode(XMLQueryError.self, from: element)

        case .ec2:
            guard case .xml(var element) = self.body else { break }
            if let errors = element.elements(forName: "Errors").first {
                element = errors
            }
            guard let errorElement = element.elements(forName: "Error").first else { break }
            apiError = try? XMLDecoder().decode(XMLQueryError.self, from: errorElement)
        }

        if let errorMessage = apiError, var code = errorMessage.code {
            // remove code prefix before #
            if let index = code.firstIndex(of: "#") {
                code = String(code[code.index(index, offsetBy: 1)...])
            }

            logger.log(level: logLevel, "AWS Error", metadata: [
                "aws-error-code": .string(code),
                "aws-error-message": .string(errorMessage.message),
            ])

            let context = AWSErrorContext(
                message: errorMessage.message,
                responseCode: self.status,
                headers: self.headers,
                additionalFields: errorMessage.additionalFields
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
    private struct XMLQueryError: Codable, APIError {
        var code: String?
        let message: String
        let additionalFields: [String: String]

        init(from decoder: Decoder) throws {
            // use `ErrorCodingKey` so we get extract additional keys from `container.allKeys`
            let container = try decoder.container(keyedBy: ErrorCodingKey.self)
            self.code = try container.decodeIfPresent(String.self, forKey: .init("Code"))
            self.message = try container.decode(String.self, forKey: .init("Message"))

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

    /// Error used by JSON output
    private struct JSONError: Decodable, APIError {
        var code: String?
        let message: String
        let additionalFields: [String: String]

        init(from decoder: Decoder) throws {
            // use `ErrorCodingKey` so we get extract additional keys from `container.allKeys`
            let container = try decoder.container(keyedBy: ErrorCodingKey.self)
            self.code = try container.decodeIfPresent(String.self, forKey: .init("__type"))
            self.message = try container.decodeIfPresent(String.self, forKey: .init("message")) ?? container.decode(String.self, forKey: .init("Message"))

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

        init(from decoder: Decoder) throws {
            // use `ErrorCodingKey` so we get extract additional keys from `container.allKeys`
            let container = try decoder.container(keyedBy: ErrorCodingKey.self)
            self.code = try container.decodeIfPresent(String.self, forKey: .init("code"))
            self.message = try container.decodeIfPresent(String.self, forKey: .init("message")) ?? container.decode(String.self, forKey: .init("Message"))

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
}
