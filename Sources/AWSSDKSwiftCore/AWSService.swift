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

/// Protocol for AWS Services
public protocol AWSService {
    /// client used to communicate with AWS
    var client: AWSClient { get }
    /// service details plus contextual info
    var context: AWSServiceContext { get }
}

public extension AWSService {
    /// Region where service is running
    var region: Region { context.region }
}
