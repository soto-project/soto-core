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

// Replicating the CryptoKit framework interface for < macOS 10.15

#if !os(Linux)

import protocol Foundation.ContiguousBytes

/// Protocol for Digest object returned from HashFunction
public protocol Digest: Sequence, ContiguousBytes, Hashable where Element == UInt8 {
    static var byteCount: Int {get}
}

/// Protocol for Digest object consisting of a byte array
protocol ByteDigest: Digest, ByteArray { }

#endif
