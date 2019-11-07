//
//  HTTPResponse.swift
//  AWSSDKSwiftCore
//
//  Created by Adam Fowler on 2019/11/6.
//
import AsyncHTTPClient
import Foundation
import NIOHTTP1

/// protocol defining requirement for creating an HTTP Response
protocol HTTPResponseDescription {
    /// Response HTTP status.
    var status: HTTPResponseStatus { get }
    /// Reponse HTTP headers.
    var headers: HTTPHeaders { get }
    /// Response body.
    var bodyData: Data? { get }
}

extension AsyncHTTPClient.HTTPClient.Response: HTTPResponseDescription {
    var bodyData: Data? {
        if let body = body {
            return body.getData(at: body.readerIndex, length: body.readableBytes, byteTransferStrategy: .noCopy)
            //var slice = body.getSlice(at: body.readerIndex, length: body.readableBytes)
            //return slice?.readData(length: body.readableBytes)
        }
        return nil
    }
}

extension AWSHTTPClient.Response: HTTPResponseDescription {
    /// Response HTTP status.
    var status: HTTPResponseStatus { return head.status }
    /// Reponse HTTP headers.
    var headers: HTTPHeaders  { return head.headers }
    /// Response body.
    var bodyData: Data? { return body }
}

