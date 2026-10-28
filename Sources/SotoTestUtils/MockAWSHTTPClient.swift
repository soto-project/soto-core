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

// Mock AWS HTTP Client for testing

import HTTPTypes
import Logging
import NIOCore
import SotoCore
import SotoXML

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif

package struct MockAWSHTTPClient: AWSHTTPClient {
    private let requestHandler: @Sendable (AWSHTTPRequest) async throws -> AWSHTTPResponse

    package init(
        requestHandler: @escaping (@Sendable (AWSHTTPRequest) async throws -> AWSHTTPResponse) = { _ in .init(response: .init(status: .ok)) }
    ) {
        self.requestHandler = requestHandler
    }

    package struct HTTPError: Error {
        let status: HTTPResponse.Status
        let code: String
        let message: String?

        package init(status: HTTPResponse.Status, code: String, message: String? = nil) {
            self.status = status
            self.code = code
            self.message = message
        }

        func response(for serviceProtocol: ServiceProtocol) -> AWSHTTPResponse {
            switch serviceProtocol {
            case .json:
                if let message {
                    AWSHTTPResponse(
                        response: .init(status: status),
                        body: .init(string: "{\"__type\":\"\(self.code)\", \"message\": \"\(message)\"}")
                    )
                } else {
                    AWSHTTPResponse(response: .init(status: status), body: .init(string: "{\"__type\":\"\(self.code)\"}"))
                }
            case .restjson:
                if let message {
                    AWSHTTPResponse(response: .init(status: status), body: .init(string: "{\"code\":\"\(self.code)\", \"message\": \"\(message)\"}"))
                } else {
                    AWSHTTPResponse(response: .init(status: status), body: .init(string: "{\"code\":\"\(self.code)\"}"))
                }
            case .restxml:
                if let message {
                    AWSHTTPResponse(
                        response: .init(status: status),
                        body: .init(string: "<Error><Code>\(self.code)</Code><Message>\(message)</Message></Error>")
                    )
                } else {
                    AWSHTTPResponse(response: .init(status: status), body: .init(string: "<Error><Code>\(self.code)</Code></Error>"))
                }
            default:
                fatalError("Protocol is not supported")
            }
        }
    }

    package init<Input: Decodable & Sendable, Output: Encodable & Sendable>(
        shapeHandler: @escaping (@Sendable (Input) async throws -> Output),
        serviceProtocol: ServiceProtocol = .restjson
    ) {
        self.requestHandler = { request in
            let inputData = try await request.body.collect(upTo: .max)
            let input: Input
            switch serviceProtocol {
            case .json, .restjson:
                input = try JSONDecoder().decode(Input.self, from: inputData)
            case .restxml:
                guard let xmlNode = try XML.Document(string: String(buffer: inputData)).rootElement() else {
                    return HTTPError(status: .internalServerError, code: "InvalidData").response(for: .restxml)
                }
                input = try XMLDecoder().decode(Input.self, from: xmlNode)
            default:
                fatalError("Protocol is not supported")
            }

            do {
                // process
                let response = try await shapeHandler(input)

                // Convert to Output AWSShape
                let outputBuffer: ByteBuffer

                switch serviceProtocol {
                case .json, .restjson:
                    let outputData = try JSONEncoder().encode(response)
                    outputBuffer = ByteBuffer(data: outputData)
                case .restxml:
                    let outputString = try XMLEncoder().encode(response)?.xmlString ?? ""
                    outputBuffer = ByteBuffer(string: outputString)
                default:
                    fatalError("Protocol is not supported")
                }
                return .init(response: .init(status: .ok), body: .init(buffer: outputBuffer))
            } catch let error as HTTPError {
                return error.response(for: serviceProtocol)
            }
        }
    }

    package func execute(
        request: AWSHTTPRequest,
        timeout: Duration,
        logger: Logger
    ) async throws -> AWSHTTPResponse {
        let response: AWSHTTPResponse
        do {
            response = try await requestHandler(request)
        } catch {
            response = .init(
                response: .init(status: .internalServerError),
                body: .init(string: "{\"__type\":\"Internal Failure\", \"message\": \"\(error)\"}")
            )
        }
        var responseHead = response.response
        if let length = response.body.length {
            responseHead.headerFields[.contentLength] = String(length)
        } else if responseHead.headerFields[.contentLength] == nil {
            responseHead.headerFields[.transferEncoding] = "chunked"
        }
        return AWSHTTPResponse(response: responseHead, body: response.body)
    }

    package static func awsError(status: HTTPResponse.Status, code: String, message: String? = nil) -> AWSHTTPResponse {
        if let message {
            AWSHTTPResponse(response: .init(status: status), body: .init(string: "{\"code\":\"\(code)\", \"message\": \"\(message)\"}"))
        } else {
            AWSHTTPResponse(response: .init(status: status), body: .init(string: "{\"code\":\"\(code)\"}"))
        }
    }
}
