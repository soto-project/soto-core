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

public import HTTPTypes

/// Standard Error type returned by Soto.
///
/// Initialized with error code and message.
public protocol AWSErrorType: Error {
    var errorCode: String { get }
    var message: String? { get }
    var response: HTTPResponse? { get }
}

/// Raw unprocessed HTTP error.
///
/// Used when we cannot extract an error code from the AWS response. Returns full body of error response
public struct AWSRawResponseError: Error {
    public let response: AWSHTTPResponse

    init(response: AWSHTTPResponse) {
        self.response = response
    }
}
