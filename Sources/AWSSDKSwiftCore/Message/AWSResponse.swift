//
//  AWSResponse.swift
//  AWSSDKSwift
//
//  Created by Adam Fowler on 2019/08/25.
//
//

import Foundation
import NIO
import NIOHTTP1
import HypertextApplicationLanguage

public struct AWSResponse {

    public let status: HTTPResponseStatus
    public var headers: [String: Any]
    public var body: Body

    init(from response: Response, serviceProtocolType: ServiceProtocolType, raw: Bool = false) throws {
        self.status = response.head.status
        self.headers = AWSResponse.createHeaders(from: response)
        self.body = try AWSResponse.createBody(from: response, serviceProtocolType: serviceProtocolType, raw: raw)
    }

    private static func createHeaders(from response: Response) -> [String: String] {
        var responseHeaders: [String: String] = [:]
        for (key, value) in response.head.headers {
            responseHeaders[key.description] = value
        }

        return responseHeaders
    }
    
    private static func createBody(from response: Response, serviceProtocolType: ServiceProtocolType, raw: Bool) throws -> Body {
        var responseBody: Body = .empty
        let data = response.body
        
        if data.isEmpty {
            return .empty
        }
        
        if raw {
            return .buffer(data)
        }
        
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
        
        return responseBody
    }
    
}
