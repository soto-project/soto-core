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

class AWSLoggingMiddleware : AWSServiceMiddleware {
    init(logFunction : @escaping (String)->() = { print($0) }) {
        self.logFunction = logFunction
    }
    
    func chain(request: AWSRequest) throws -> AWSRequest {
        print("Request:")
        print(request)
        return request
    }
    func chain(responseBody: Body) throws -> Body {
        print("Response:")
        switch responseBody {
        case .xml(let element):
            print(element.description)
        case .json(let data):
            print(String(data: data, encoding: .utf8) ?? "Failed to convert JSON response to UTF8")
        case .buffer(let data):
            print("Data \(data.count) bytes")
        case .text(let string):
            print(string)
        default:
            break
        }
        return responseBody
    }
    
    let logFunction : (String)->()
}

#endif //DEBUG
