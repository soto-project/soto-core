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
    var client: AWSClient { get }
    var context: AWSServiceContext { get }
    func transform(_: (AWSServiceContext) -> AWSServiceContext) -> Self
}

public extension AWSService {
    /// return new AWSServiceConfig with new timeout value
    func with(timeout: TimeAmount) -> Self {
        return transform { $0.with(timeout: timeout) }
    }

    /// return new AWSServiceConfig logging to specified Logger
    func logging(to logger: Logger) -> Self {
        return transform { $0.logging(to: logger) }
    }
}
