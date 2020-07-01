//===----------------------------------------------------------------------===//
//
// This source file is part of the AWSSDKSwift open source project
//
// Copyright (c) 2017-2020 the AWSSDKSwift project authors
// Licensed under Apache License v2.0
//
// See LICENSE.txt for license information
// See CONTRIBUTORS.txt for the list of AWSSDKSwift project authors
//
// SPDX-License-Identifier: Apache-2.0
//
//===----------------------------------------------------------------------===//

import class Foundation.JSONSerialization
import class Foundation.JSONDecoder
import Logging
import NIO
import NIOHTTP1
import AWSXML

/// Structure encapsulating a processed HTTP Response
public struct AWSResponse {

    /// response status
    public let status: HTTPResponseStatus
    /// response headers
    public var headers: [String: Any]
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
        var responseHeaders: [String: String] = [:]
        for (key, value) in response.headers {
            // use lowercase for all headers
            responseHeaders[key.lowercased()] = value
        }
        self.headers = responseHeaders

        // body
        guard let body = response.body,
            body.readableBytes > 0 else {
            self.body = .empty
            return
        }

        if raw {
            self.body = .raw(.byteBuffer(body))
            return
        }

        guard let data = body.getData(at: body.readerIndex, length: body.readableBytes, byteTransferStrategy: .noCopy) else {
            self.body = .empty
            return
        }

        var responseBody: Body = .empty

        switch serviceProtocol {
        case .json, .restjson:
            responseBody = .json(data)

        case .restxml, .query:
            let xmlDocument = try XML.Document(data: data)
            if let element = xmlDocument.rootElement() {
                responseBody = .xml(element)
            }

        case .ec2:
            let xmlDocument = try XML.Document(data: data)
            if let element = xmlDocument.rootElement() {
                responseBody = .xml(element)
            }
        }
        self.body = responseBody
    }
    
    /// return new response with middleware applied
    func applyMiddlewares(_ middlewares: [AWSServiceMiddleware]) throws -> AWSResponse {
        var awsResponse = self
        // apply middleware to respons
        for middleware in middlewares {
            awsResponse = try middleware.chain(response: awsResponse)
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

        // if required apply hypertext application language transform to body
        let body = try getHypertextApplicationLanguageBody()
        
        var outputDict: [String: Any] = [:]
        switch body {
        case .json(let data):
            outputDict = try JSONSerialization.jsonObject(with: data, options: []) as? [String: Any] ?? [:]
            // if payload path is set then the decode will expect the payload to decode to the relevant member variable
            if let payloadKey = payloadKey {
                outputDict = [payloadKey : outputDict]
            }

        case .xml(let node):
            var outputNode = node
            // if payload path is set then the decode will expect the payload to decode to the relevant member variable. Most CloudFront responses have this.
            if let payloadKey = payloadKey {
                // set output node name
                outputNode.name = payloadKey
                // create parent node and add output node and set output node to parent
                let parentNode = XML.Element(name: "Container")
                parentNode.addChild(outputNode)
                outputNode = parentNode
            } else if let child = node.children(of:.element)?.first as? XML.Element, (node.name == operation + "Response" && child.name == operation + "Result") {
                outputNode = child
            }

            // add header values to xmlnode as children nodes, so they can be decoded into the response object
            for (key, value) in self.headers {
                let headerParams = Output.headerParams
                if let index = headerParams.firstIndex(where: { $0.key.lowercased() == key.lowercased() }) {
                    guard let stringValue = value as? String else { continue }
                    let node = XML.Element(name: headerParams[index].key, stringValue: stringValue)
                    outputNode.addChild(node)
                }
            }
            // add status code to output dictionary
            if let statusCodeParam = Output.statusCodeParam {
                let node = XML.Element(name: statusCodeParam, stringValue: "\(self.status.code)")
                outputNode.addChild(node)
            }
            return try XMLDecoder().decode(Output.self, from: outputNode)

        case .raw(let payload):
            if let payloadKey = payloadKey {
                outputDict[payloadKey] = payload
            }

        default:
            break
        }

        // add header values to output dictionary, so they can be decoded into the response object
        for (key, value) in self.headers {
            let headerParams = Output.headerParams
            if let index = headerParams.firstIndex(where: { $0.key.lowercased() == key.lowercased() }) {
                // check we can convert to a String. If not just put value straight into output dictionary
                guard let stringValue = value as? String else {
                    outputDict[headerParams[index].key] = value
                    continue
                }
                if let number = Double(stringValue) {
                    outputDict[headerParams[index].key] = number.truncatingRemainder(dividingBy: 1) == 0 ? Int(number) : number
                } else if let boolean = Bool(stringValue) {
                    outputDict[headerParams[index].key] = boolean
                } else {
                    outputDict[headerParams[index].key] = stringValue
                }
            }
        }
        // add status code to output dictionary
        if let statusCodeParam = Output.statusCodeParam {
            outputDict[statusCodeParam] = self.status.code
        }

        return try decoder.decode(Output.self, from: outputDict)
    }
    
    /// extract error code and message from AWSResponse
    func generateError(serviceConfig: AWSServiceConfig, logger: Logger) -> Error? {
        var apiError: APIError? = nil
        switch serviceConfig.serviceProtocol {
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

        case .restjson:
            guard case .json(let data) = self.body else { break }
            apiError = try? JSONDecoder().decode(RESTJSONError.self, from: data)
            if apiError?.code == nil {
                apiError?.code = self.headers["x-amzn-errortype"] as? String
            }

        case .json:
            guard case .json(let data) = self.body else { break }
            apiError = try? JSONDecoder().decode(JSONError.self, from: data)

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

            logger.error("AWS error", metadata: [
                "aws-error-code": .string(code),
                "aws-error-message": .string(errorMessage.message)
            ])

            for errorType in serviceConfig.possibleErrorTypes {
                if let error = errorType.init(errorCode: code, message: errorMessage.message) {
                    return error
                }
            }
            if let error = AWSClientError(errorCode: code, message: errorMessage.message) {
                return error
            }

            if let error = AWSServerError(errorCode: code, message: errorMessage.message) {
                return error
            }

            return AWSResponseError(errorCode: code, message: errorMessage.message)
        }
        
        return nil
    }

    private struct XMLQueryError: Codable, APIError {
        var code: String?
        var message: String

        private enum CodingKeys: String, CodingKey {
            case code = "Code"
            case message = "Message"
        }
    }
    private struct JSONError: Codable, APIError {
        var code: String?
        var message: String

        private enum CodingKeys: String, CodingKey {
            case code = "__type"
            case message = "message"
        }
    }
    private struct RESTJSONError: Codable, APIError {
        var code: String?
        var message: String

        private enum CodingKeys: String, CodingKey {
            case code = "code"
            case message = "message"
        }
    }
}

fileprivate protocol APIError {
    var code: String? {get set}
    var message: String {get set}
}

