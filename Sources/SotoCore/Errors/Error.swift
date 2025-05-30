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

import NIOHTTP1

/// Standard Error type returned by Soto.
///
/// Initialized with error code and message.
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
        "\(self)"
    }

    public var message: String? {
        context?.message
    }
}

/// Service that has extended error information
public protocol AWSServiceErrorType: AWSErrorType {
    static var errorCodeMap: [String: AWSErrorShape.Type] { get }
}

/// Additional information about error
public struct AWSErrorContext {
    public let message: String
    public let responseCode: HTTPResponseStatus
    public let headers: HTTPHeaders
    public let additionalFields: [String: String]
    public let extendedError: AWSErrorShape?

    internal init(
        message: String,
        responseCode: HTTPResponseStatus,
        headers: HTTPHeaders = [:],
        additionalFields: [String: String] = [:],
        extendedError: AWSErrorShape? = nil
    ) {
        self.message = message
        self.responseCode = responseCode
        self.headers = headers
        self.additionalFields = additionalFields
        self.extendedError = extendedError
    }
}

/// Response Error type returned by Soto if the error code is unrecognised
public struct AWSResponseError: AWSErrorType {
    public let errorCode: String
    public let context: AWSErrorContext?

    public init(errorCode: String) {
        self.errorCode = errorCode
        self.context = nil
    }

    public init(errorCode: String, context: AWSErrorContext) {
        self.errorCode = errorCode
        self.context = context
    }

    public var description: String {
        "\(self.errorCode): \(self.message ?? "")"
    }
}

/// Raw unprocessed error.
///
/// Used when we cannot extract an error code from the AWS response. Returns full body of error response
public struct AWSRawError: Error, CustomStringConvertible {
    public let rawBody: String?
    public let context: AWSErrorContext

    init(rawBody: String?, context: AWSErrorContext) {
        self.rawBody = rawBody
        self.context = context
    }

    public var description: String {
        "Unhandled error, code: \(self.context.responseCode)\(self.rawBody.map { ", body: \($0)" } ?? "")"
    }
}

extension AWSErrorContext: Sendable {}
