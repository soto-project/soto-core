//===----------------------------------------------------------------------===//
//
// This source file is part of the Soto for AWS open source project
//
// Copyright (c) 2020 the Soto project authors
// Licensed under Apache License v2.0
//
// See LICENSE.txt for license information
// See CONTRIBUTORS.txt for the list of Soto project authors
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
}

extension AWSService {
    /// Region where service is running
    public var region: Region { return config.region }
    /// The url to use in requests
    public var endpoint: String { return config.endpoint }
    /// The EventLoopGroup service is using
    public var eventLoopGroup: EventLoopGroup { return client.eventLoopGroup }

    /// generate a signed URL
    /// - parameters:
    ///     - url : URL to sign
    ///     - httpMethod: HTTP method to use (.GET, .PUT, .PUSH etc)
    ///     - httpHeaders: Headers that are to be used with this URL. Be sure to include these headers when you used the returned URL
    ///     - expires: How long before the signed URL expires
    ///     - logger: Logger to output to
    /// - returns:
    ///     A signed URL
    public func signURL(
        url: URL,
        httpMethod: HTTPMethod,
        headers: HTTPHeaders = HTTPHeaders(),
        expires: Int = 86400,
        logger: Logger = AWSClient.loggingDisabled
    ) -> EventLoopFuture<URL> {
        return self.client.signURL(url: url, httpMethod: httpMethod, headers: headers, expires: expires, serviceConfig: self.config, logger: logger)
    }
}
