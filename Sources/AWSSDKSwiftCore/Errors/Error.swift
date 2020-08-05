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

import NIOHTTP1

/// Standard Error type returned by aws-sdk-swift. Initialized with error code and message. Must provide an implementation of var description : String
public protocol AWSErrorType: Error, CustomStringConvertible {
    init?(errorCode: String, message: String?)
}

extension AWSErrorType {
    public var localizedDescription: String {
        return description
    }
}

/// Standard Response Error type returned by aws-sdk-swift. If the error is unrecognised then this is returned
public struct AWSResponseError: AWSErrorType {
    public let errorCode: String
    public let message: String?

    public init(errorCode: String, message: String?) {
        self.errorCode = errorCode
        self.message = message
    }

    public var description: String {
        return "\(self.errorCode): \(self.message ?? "")"
    }
}

/// Unrecognised error. Used when we cannot recognise the error code from the AWS response
public struct AWSError: Error, CustomStringConvertible {
    public let message: String
    public let rawBody: String?
    public let statusCode: HTTPResponseStatus

    init(statusCode: HTTPResponseStatus, message: String, rawBody: String?) {
        self.statusCode = statusCode
        self.message = message
        self.rawBody = rawBody
    }

    public var description: String {
        return "\(self.message), code: \(self.statusCode.code)\(self.rawBody.map { ", body: \($0)" } ?? "")"
    }
}
