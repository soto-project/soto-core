//===----------------------------------------------------------------------===//
//
// This source file is part of the Soto for AWS open source project
//
// Copyright (c) 2017-2026 the Soto project authors
// Licensed under Apache License v2.0
//
// See LICENSE.txt for license information
// See CONTRIBUTORS.txt for the list of Soto project authors
//
// SPDX-License-Identifier: Apache-2.0
//
//===----------------------------------------------------------------------===//

public import HTTPTypes

extension HTTPField.Name {
    @inlinable
    static var xAmzTarget: Self {
        .init("X-Amz-Target")!
    }

    @inlinable
    static var xAmzRequestID: Self {
        .init("x-amz-request-id")!
    }

    @inlinable
    static var xAmzRequestIDv2: Self {
        .init("x-amz-requestid")!
    }

    @inlinable
    static var xAmzDecodedContentLength: Self {
        .init("X-Amz-Decoded-Content-Length")!
    }

    @inlinable
    static var xAmzSdkChecksumAlgorithm: Self {
        .init("X-Amz-Sdk-Checksum-Algorithm")!
    }

    @inlinable
    static var xAmznErrorType: Self {
        .init("X-Amzn-Errortype")!
    }

    @inlinable
    static var xAmzSSOBearerToken: Self {
        .init("x-amz-sso_bearer_token")!
    }

    @inlinable
    static var dPoP: Self {
        .init("DPoP")!
    }

}
