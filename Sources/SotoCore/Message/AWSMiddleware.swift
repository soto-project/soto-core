//===----------------------------------------------------------------------===//
//
// This source file is part of the Soto for AWS open source project
//
// Copyright (c) 2017-2022 the Soto project authors
// Licensed under Apache License v2.0
//
// See LICENSE.txt for license information
// See CONTRIBUTORS.txt for the list of Soto project authors
//
// SPDX-License-Identifier: Apache-2.0
//
//===----------------------------------------------------------------------===//

/// Context object sent to `AWSServiceMiddleware` `chain` functions
public struct AWSMiddlewareContext {
    public let options: AWSServiceConfig.Options
}

/// Middleware protocol. Process requests before they are sent to AWS and process responses before they are converted into output shapes
public protocol AWSServiceMiddleware: _SotoSendableProtocol {
    /// Process AWSRequest before it is converted to a HTTPClient Request to be sent to AWS
    func chain(request: AWSRequest, context: AWSMiddlewareContext) throws -> AWSRequest

    /// Process response before it is converted to an output AWSShape
    func chain(response: AWSResponse, context: AWSMiddlewareContext) throws -> AWSResponse
}

/// Default versions of protocol functions
public extension AWSServiceMiddleware {
    func chain(request: AWSRequest, context: AWSMiddlewareContext) throws -> AWSRequest {
        return request
    }

    func chain(response: AWSResponse, context: AWSMiddlewareContext) throws -> AWSResponse {
        return response
    }
}
