//
//  AWSResponse.swift
//  AWSSDKSwift
//
//  Created by Adam Fowler on 2019/08/25.
//
//

import NIO
import NIOHTTP1

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
    init(from response: AWSHTTPResponse, serviceProtocolType: ServiceProtocolType, raw: Bool = false) throws {
        self.status = response.status
        
        // headers
        var responseHeaders: [String: String] = [:]
        for (key, value) in response.headers {
            responseHeaders[key] = value
        }
        self.headers = responseHeaders
        
        // body
        guard let body = response.body,
            body.readableBytes > 0,
            let data = body.getData(at: body.readerIndex, length: body.readableBytes, byteTransferStrategy: .noCopy) else {
                self.body = .empty
                return
        }
        
        if raw {
            self.body = .buffer(data)
            return
        }
        
        var responseBody: Body = .empty
        
        switch serviceProtocolType {
        case .json, .restjson:
            responseBody = .json(data)
            
        case .restxml, .query:
            let xmlDocument = try XML.Document(data: data)
            if let element = xmlDocument.rootElement() {
                responseBody = .xml(element)
            }
            
        case .other(let proto):
            switch proto.lowercased() {
            case "ec2":
                let xmlDocument = try XML.Document(data: data)
                if let element = xmlDocument.rootElement() {
                    responseBody = .xml(element)
                }
                
            default:
                responseBody = .buffer(data)
            }
        }
        self.body = responseBody
    }
}
