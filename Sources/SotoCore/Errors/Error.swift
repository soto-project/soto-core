//===----------------------------------------------------------------------===//
//
// This source file is part of the Soto for AWS open source project
//
// Copyright (c) 2017-2022 the Soto project authors
// Licensed under Apache License v2.0
//
// See LICENSE.txt for license information
// See CONTRIBUTORS.txt for the list of Soto project authors
//
// SPDX-License-Identifier: Apache-2.0
//
//===----------------------------------------------------------------------===//

#if compiler(>=5.6)
@preconcurrency import NIOHTTP1
#else
import NIOHTTP1
#endif

/// Standard Error type returned by Soto. Initialized with error code and message. Must provide an implementation of var description : String
public protocol AWSErrorType: Error, CustomStringConvertible {
    /// initialize error
    init?(errorCode: String, context: AWSErrorContext)
    /// Error code return by AWS
    var errorCode: String { get }
    /// additional context information related to the error
    var context: AWSErrorContext? { get }
}

extension AWSErrorType {
    public var localizedDescription: String {
        return description
    }

    public var message: String? {
        return context?.message
    }
}

/// Additional information about error
public struct AWSErrorContext {
    public let message: String
    public let responseCode: HTTPResponseStatus
    public let headers: HTTPHeaders
    public let additionalFields: [String: String]

    internal init(
        message: String,
        responseCode: HTTPResponseStatus,
        headers: HTTPHeaders = [:],
        additionalFields: [String: String] = [:]
    ) {
        self.message = message
        self.responseCode = responseCode
        self.headers = headers
        self.additionalFields = additionalFields
    }
}

/// Standard Response Error type returned by Soto. If the error code is unrecognised then this is returned
public struct AWSResponseError: AWSErrorType {
    public let errorCode: String
    public let context: AWSErrorContext?

    public init(errorCode: String, context: AWSErrorContext) {
        self.errorCode = errorCode
        self.context = context
    }

    public var description: String {
        return "\(self.errorCode): \(self.message ?? "")"
    }
}

/// Unrecognised error. Used when we cannot extract an error code from the AWS response. Returns full body of error response
public struct AWSRawError: Error, CustomStringConvertible {
    public let rawBody: String?
    public let context: AWSErrorContext

    init(rawBody: String?, context: AWSErrorContext) {
        self.rawBody = rawBody
        self.context = context
    }

    public var description: String {
        return "Unhandled error, code: \(self.context.responseCode)\(self.rawBody.map { ", body: \($0)" } ?? "")"
    }
}

#if compiler(>=5.6)
extension AWSErrorContext: Sendable {}
#endif
