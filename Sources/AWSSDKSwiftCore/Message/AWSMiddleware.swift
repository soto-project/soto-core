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
    
    /// Process responseBody before it is converted to an output AWSShape
    func chain(responseBody: Body) throws -> Body
}

/// Default versions of protocol functions
public extension AWSServiceMiddleware {
    func chain(request: AWSRequest) throws -> AWSRequest {
        return request
    }
    func chain(responseBody: Body) throws -> Body {
        return responseBody
    }
}

#if DEBUG

/// Middleware class that outputs the contents of requests being sent to AWS and the bodies of the responses received
public class AWSLoggingMiddleware : AWSServiceMiddleware {
    
    /// initialize AWSLoggingMiddleware class
    /// - parameters:
    ///     - log: Function to call with logging output
    init(log : @escaping (String)->() = { print($0) }) {
        self.log = log
    }
    
    func getBodyOutput(_ body: Body) -> String {
        var output = ""
        switch body {
        case .xml(let element):
            output += "\n"
            output += element.description
        case .json(let data):
            output += "\n"
            output += String(data: data, encoding: .utf8) ?? "Failed to convert JSON response to UTF8"
        case .buffer(let data):
            output += "data (\(data.count) bytes)"
        case .text(let string):
            output += "\n\(string)"
        case .empty:
            output += "empty"
        default:
            break
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
        return output + "\n]"
    }
    
    /// output request
    public func chain(request: AWSRequest) throws -> AWSRequest {
        log("Request: \(request.operation)")
        log("\(request.httpMethod) \(request.url)")
        log("Headers: " + getHeadersOutput(request.httpHeaders))
        log("Body: " + getBodyOutput(request.body))
        return request
    }
    
    /// output response
    public func chain(responseBody: Body) throws -> Body {
        var output = "Response: "
        output += getBodyOutput(responseBody)
        log(output)
        return responseBody
    }
    
    let log : (String)->()
}

#endif //DEBUG
