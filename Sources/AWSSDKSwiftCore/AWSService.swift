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
