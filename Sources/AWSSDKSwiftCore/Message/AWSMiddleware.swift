//
//  AWSMiddleware.swift
//  AWSSDKSwift
//
//  Created by Yuki Takei/Adam Fowler on 2019/08/17.
//
//

/// Middleware protocol. Gives ability to process requests before they are sent to AWS and process responses before they are converted into output shapes
public protocol AWSServiceMiddleware {
    
    /// Process AWSRequest before it is converted to a HTTPClient Request to be sent to AWS
    func chain(request: AWSRequest) throws -> AWSRequest
    
    /// Process response before it is converted to an output AWSShape
    func chain(response: AWSResponse) throws -> AWSResponse
}

/// Default versions of protocol functions
public extension AWSServiceMiddleware {
    func chain(request: AWSRequest) throws -> AWSRequest {
        return request
    }
    func chain(response: AWSResponse) throws -> AWSResponse {
        return response
    }
}

/// Middleware class that outputs the contents of requests being sent to AWS and the bodies of the responses received
public class AWSLoggingMiddleware : AWSServiceMiddleware {
    
    /// initialize AWSLoggingMiddleware class
    /// - parameters:
    ///     - log: Function to call with logging output
    public init(log : @escaping (String)->() = { print($0) }) {
        self.log = log
    }
    
    func getBodyOutput(_ body: Body) -> String {
        var output = ""
        switch body {
        case .xml(let element):
            output += "\n  "
            output += element.description
        case .json(let data):
            output += "\n  "
            output += String(data: data, encoding: .utf8) ?? "Failed to convert JSON response to UTF8"
        case .buffer(let byteBuffer):
            output += "data (\(byteBuffer.readableBytes) bytes)"
        case .text(let string):
            output += "\n  \(string)"
        case .empty:
            output += "empty"
        }
        return output
    }

    func getHeadersOutput(_ headers: [String: Any?]) -> String {
        if headers.count == 0 {
            return "[]"
        }
        var output = "["
        for header in headers {
            output += "\n    \(header.key) : \(header.value ?? "nil")"
        }
        return output + "\n  ]"
    }
    
    /// output request
    public func chain(request: AWSRequest) throws -> AWSRequest {
        log("Request:")
        log("  \(request.operation)")
        log("  \(request.httpMethod) \(request.url)")
        log("  Headers: " + getHeadersOutput(request.httpHeaders))
        log("  Body: " + getBodyOutput(request.body))
        return request
    }
    
    /// output response
    public func chain(response: AWSResponse) throws -> AWSResponse {
        log("Response:")
        log("  Status : \(response.status.code)")
        log("  Headers: " + getHeadersOutput(response.headers))
        log("  Body: " + getBodyOutput(response.body))
        return response
    }
    
    let log : (String)->()
}
