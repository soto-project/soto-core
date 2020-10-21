//===----------------------------------------------------------------------===//
//
// This source file is part of the Soto for AWS open source project
//
// Copyright (c) 2017-2020 the Soto project authors
// Licensed under Apache License v2.0
//
// See LICENSE.txt for license information
// See CONTRIBUTORS.txt for the list of Soto project authors
//
// SPDX-License-Identifier: Apache-2.0
//
//===----------------------------------------------------------------------===//

import NIOHTTP1

/// Standard Error type returned by Soto. Initialized with error code and message. Must provide an implementation of var description : String
public protocol AWSErrorType: Error, CustomStringConvertible {
    init?(errorCode: String, message: String?, statusCode: HTTPResponseStatus?, requestId: String?)
}

extension AWSErrorType {
    public var localizedDescription: String {
        return description
    }
}

/// Standard Response Error type returned by Soto. If the error code is unrecognised then this is returned
public struct AWSResponseError: AWSErrorType {
    public let errorCode: String
    public let message: String?
    public let statusCode: HTTPResponseStatus?
    public let requestId: String?

    public init(errorCode: String, message: String?, statusCode: HTTPResponseStatus?, requestId: String?) {
        self.errorCode = errorCode
        self.message = message
        self.statusCode = statusCode
        self.requestId = requestId
    }

    public var description: String {
        return "\(self.errorCode): \(self.message ?? "")"
    }
}

/// Unrecognised error. Used when we cannot extract an error code from the AWS response
public struct AWSError: Error, CustomStringConvertible {
    public let message: String
    public let statusCode: HTTPResponseStatus
    public let rawBody: String?
    public let requestId: String?

    init(message: String, statusCode: HTTPResponseStatus, rawBody: String?, requestId: String?) {
        self.statusCode = statusCode
        self.message = message
        self.rawBody = rawBody
        self.requestId = requestId
    }

    public var description: String {
        return "\(self.message), code: \(self.statusCode.code)\(self.rawBody.map { ", body: \($0)" } ?? "")"
    }
}
