//===----------------------------------------------------------------------===//
//
// This source file is part of the AWSSDKSwift open source project
//
// Copyright (c) 2017-2020 the AWSSDKSwift project authors
// Licensed under Apache License v2.0
//
// See LICENSE.txt for license information
// See CONTRIBUTORS.txt for the list of AWSSDKSwift project authors
//
// SPDX-License-Identifier: Apache-2.0
//
//===----------------------------------------------------------------------===//

import AWSSignerV4
import struct Foundation.TimeInterval

public protocol ExpiringCredential: Credential {
    func isExpiring(within: TimeInterval) -> Bool
}

public extension ExpiringCredential {
    var isExpired: Bool {
        isExpiring(within: 0)
    }
}

