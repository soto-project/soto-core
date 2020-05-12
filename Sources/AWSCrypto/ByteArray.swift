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

/// Protocol for object encapsulating an array of bytes
protocol ByteArray: Sequence, ContiguousBytes, Hashable where Element == UInt8 {
    init(bytes: [UInt8])
    var bytes: [UInt8] { get set }
}

extension ByteArray {
    public func makeIterator() -> Array<UInt8>.Iterator {
        return self.bytes.makeIterator()
    }

    public init?(bufferPointer: UnsafeRawBufferPointer) {
        self.init(bytes: [UInt8](bufferPointer))
    }

    public func withUnsafeBytes<R>(_ body: (UnsafeRawBufferPointer) throws -> R) rethrows -> R {
        return try bytes.withUnsafeBytes(body)
    }
}

#endif
