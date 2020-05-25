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

import NIO
import NIOHTTP1
@_implementationOnly import AWSXML

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
            responseHeaders[key] = value
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
}
