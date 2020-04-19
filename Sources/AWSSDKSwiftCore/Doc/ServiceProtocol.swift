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

public enum ServiceProtocol {
    case json(version: String)
    case restjson
    case restxml
    case query
    case ec2
}

extension ServiceProtocol {
    public var contentType: String? {
        switch self {
        case .json(let version):
            return "application/x-amz-json-\(version)"
        case .restjson:
            return "application/json"
        case .restxml:
            return nil
        case .query, .ec2:
            return "application/x-www-form-urlencoded; charset=utf-8"
        }
    }
}
