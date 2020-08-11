//===----------------------------------------------------------------------===//
//
// This source file is part of the AWSSDKSwift open source project
//
// Copyright (c) 2020 the AWSSDKSwift project authors
// Licensed under Apache License v2.0
//
// See LICENSE.txt for license information
// See CONTRIBUTORS.txt for the list of AWSSDKSwift project authors
//
// SPDX-License-Identifier: Apache-2.0
//
//===----------------------------------------------------------------------===//

import Foundation

public protocol AWSService {
    /// client used to communicate with AWS
    var client: AWSClient { get }
    /// service context details
    var config: AWSServiceConfig { get }
    /// service context details
    var context: AWSServiceContext { get }

    /// create copy of service with new context
    func withNewContext(_: (AWSServiceContext) -> AWSServiceContext) -> Self
}

extension AWSService {
    /// Region where service is running
    public var region: Region { return config.region }
    /// The url to use in requests
    public var endpoint: String { return config.endpoint }
    
    /// generate a signed URL
    /// - parameters:
    ///     - url : URL to sign
    ///     - httpMethod: HTTP method to use ("GET", "PUT", "PUSH" etc)
    ///     - expires: How long before the signed URL expires
    /// - returns:
    ///     A signed URL
    public func signURL(url: URL, httpMethod: String, expires: Int = 86400) -> EventLoopFuture<URL> {
        return self.client.signURL(url: url, httpMethod: httpMethod, expires: expires, config: self.config, context: self.context)
    }
}

extension AWSService {
    public func delegating(to eventLoop: EventLoop) -> Self {
        return withNewContext { $0.delegating(to: eventLoop) }
    }

    public func logging(to logger: Logger) -> Self {
        return withNewContext { $0.logging(to: logger) }
    }

    /// return new AWSServiceConfig with new timeout value
    public func timingOut(after timeout: TimeAmount) -> Self {
        return withNewContext { $0.timingOut(after: timeout) }
    }
}
