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

import Baggage

private enum RequestIdKey: Baggage.Key {
    typealias Value = Int
    static var name: String? { "aws-request-id" }
}

private enum AWSServiceKey: Baggage.Key {
    typealias Value = String
    static var name: String? { "aws-service" }
}

private enum AWSOperationKey: Baggage.Key {
    typealias Value = String
    static var name: String? { "aws-operation" }
}

extension Baggage {
    var awsService: String? {
        get {
            self[_key: AWSServiceKey.self]
        }
        set {
            self[_key: AWSServiceKey.self] = newValue
        }
    }

    var awsOperation: String? {
        get {
            self[_key: AWSOperationKey.self]
        }
        set {
            self[_key: AWSOperationKey.self] = newValue
        }
    }

    var awsRequestId: Int? {
        get {
            self[_key: RequestIdKey.self]
        }
        set {
            self[_key: RequestIdKey.self] = newValue
        }

    }
}
