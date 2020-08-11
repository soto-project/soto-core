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

public struct AWSServiceContext {
    public var eventLoop: EventLoop?
    public var logger: Logger
    public var timeout: TimeAmount

    public init(eventLoop: EventLoop? = nil, logger: Logger = AWSClient.loggingDisabled, timeout: TimeAmount = .seconds(20)) {
        self.eventLoop = eventLoop
        self.logger = logger
        self.timeout = timeout
    }

    public func delegating(to eventLoop: EventLoop) -> AWSServiceContext {
        var context = self
        context.eventLoop = eventLoop
        return context
    }

    public func logging(to logger: Logger) -> AWSServiceContext {
        var context = self
        context.logger = logger
        return context
    }

    public func timingOut(after timeout: TimeAmount) -> AWSServiceContext {
        var context = self
        context.timeout = timeout
        return context
    }
}
