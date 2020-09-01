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

// Replicating the CryptoKit framework interface for < macOS 10.15

#if !os(Linux)

import protocol Foundation.ContiguousBytes

/// Symmetric key object
public struct SymmetricKey: ContiguousBytes {
    let bytes: [UInt8]

    public var bitCount: Int {
        return self.bytes.count * 8
    }

    public init<D>(data: D) where D: ContiguousBytes {
        let bytes = data.withUnsafeBytes { buffer in
            return [UInt8](buffer)
        }
        self.bytes = bytes
    }

    public func withUnsafeBytes<R>(_ body: (UnsafeRawBufferPointer) throws -> R) rethrows -> R {
        return try self.bytes.withUnsafeBytes(body)
    }
}

#endif
