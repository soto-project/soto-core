import AsyncHTTPClient
import Foundation
import NIO

/// comply with AWSHTTPClient protocol
extension AsyncHTTPClient.HTTPClient: AWSHTTPClient {
    func execute(request: AWSHTTPRequest, timeout: TimeAmount) -> EventLoopFuture<AWSHTTPResponse> {
        let requestBody: AsyncHTTPClient.HTTPClient.Body?
        if let body = request.body {
            requestBody = AsyncHTTPClient.HTTPClient.Body.byteBuffer(body)
        } else {
            requestBody = nil
        }
        do {
            let asyncRequest = try AsyncHTTPClient.HTTPClient.Request(url: request.url, method: request.method, headers: request.headers, body: requestBody)
            return execute(request: asyncRequest, deadline: .now() + timeout).map { $0 }
        } catch {
            return eventLoopGroup.next().makeFailedFuture(error)
        }
    }
}

extension AsyncHTTPClient.HTTPClient.Response: AWSHTTPResponse {}
