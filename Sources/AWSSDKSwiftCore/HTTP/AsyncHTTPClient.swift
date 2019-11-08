import AsyncHTTPClient
import Foundation
import NIO

/// comply with AWSHTTPClient protocol
extension AsyncHTTPClient.HTTPClient: AWSHTTPClient {
    func execute(request: AWSHTTPRequest, timeout: TimeAmount) -> EventLoopFuture<AWSHTTPResponse> {
        let requestBody: AsyncHTTPClient.HTTPClient.Body?
        if let bodyData = request.bodyData {
            requestBody = AsyncHTTPClient.HTTPClient.Body.data(bodyData)
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

extension AsyncHTTPClient.HTTPClient.Response: AWSHTTPResponse {
    var bodyData: Data? {
        if let body = self.body {
            return body.getData(at: body.readerIndex, length: body.readableBytes, byteTransferStrategy: .noCopy)
        }
        return nil
    }
}
