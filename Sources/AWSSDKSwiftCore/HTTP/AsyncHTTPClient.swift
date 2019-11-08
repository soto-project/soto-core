import AsyncHTTPClient
import Foundation
import NIO

/// comply with AWSHTTPClient protocol
extension AsyncHTTPClient.HTTPClient: AWSHTTPClient {
    func execute(request: AWSHTTPRequest, deadline: NIODeadline) -> EventLoopFuture<AWSHTTPResponse> {
        let requestBody: AsyncHTTPClient.HTTPClient.Body?
        if let body = request.body {
            requestBody = AsyncHTTPClient.HTTPClient.Body.data(body)
        } else {
            requestBody = nil
        }
        do {
            let asyncRequest = try AsyncHTTPClient.HTTPClient.Request(url: request.url, method: request.method, headers: request.headers, body: requestBody)
            
            return execute(request: asyncRequest, deadline: deadline)
                .map { response in
                    let bodyData: Data?
                    if let body = response.body {
                        bodyData = body.getData(at: body.readerIndex, length: body.readableBytes, byteTransferStrategy: .noCopy)
                    } else {
                        bodyData = nil
                    }
                    return AWSHTTPResponse(status: response.status, headers: response.headers, body: bodyData)
            }
        } catch {
            return eventLoopGroup.next().makeFailedFuture(error)
        }
    }
}
