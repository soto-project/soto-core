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
    package static var xAmzTarget: Self {
        .init("X-Amz-Target")!
    }

    @inlinable
    package static var xAmzRequestID: Self {
        .init("x-amz-request-id")!
    }

    @inlinable
    package static var xAmzRequestIDv2: Self {
        .init("x-amz-requestid")!
    }

    @inlinable
    package static var xAmzDecodedContentLength: Self {
        .init("X-Amz-Decoded-Content-Length")!
    }

    @inlinable
    package static var xAmzSdkChecksumAlgorithm: Self {
        .init("X-Amz-Sdk-Checksum-Algorithm")!
    }

    @inlinable
    package static var xAmznErrorType: Self {
        .init("X-Amzn-Errortype")!
    }

    @inlinable
    package static var xAmzSSOBearerToken: Self {
        .init("x-amz-sso_bearer_token")!
    }

    @inlinable
    package static var dPoP: Self {
        .init("DPoP")!
    }

    @inlinable
    package static var contentMD5: Self {
        .init("Content-MD5")!
    }

    @inlinable
    package static var xAmzChecksumSHA1: Self {
        .init("x-amz-checksum-sha1")!
    }

    @inlinable
    package static var xAmzChecksumCRC32: Self {
        .init("x-amz-checksum-crc32")!
    }

    @inlinable
    package static var xAmzChecksumCRC32C: Self {
        .init("x-amz-checksum-crc32c")!
    }

    @inlinable
    package static var xAmzChecksumSHA256: Self {
        .init("x-amz-checksum-sha256")!
    }

}
