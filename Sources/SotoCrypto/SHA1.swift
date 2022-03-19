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

// Replicating the CryptoKit framework interface for < macOS 10.15

#if !os(Linux)

import CommonCrypto

public extension Insecure {
    struct SHA1Digest: ByteDigest {
        public static var byteCount: Int { return Int(CC_SHA1_DIGEST_LENGTH) }
        public var bytes: [UInt8]
    }

    struct SHA1: CCHashFunction {
        public typealias Digest = SHA1Digest
        public static var algorithm: CCHmacAlgorithm { return CCHmacAlgorithm(kCCHmacAlgSHA1) }
        var context: CC_SHA1_CTX

        public static func hash(bufferPointer: UnsafeRawBufferPointer) -> Self.Digest {
            var digest: [UInt8] = .init(repeating: 0, count: Digest.byteCount)
            CC_SHA1(bufferPointer.baseAddress, CC_LONG(bufferPointer.count), &digest)
            return .init(bytes: digest)
        }

        public init() {
            self.context = CC_SHA1_CTX()
            CC_SHA1_Init(&self.context)
        }

        public mutating func update(bufferPointer: UnsafeRawBufferPointer) {
            CC_SHA1_Update(&self.context, bufferPointer.baseAddress, CC_LONG(bufferPointer.count))
        }

        public mutating func finalize() -> Self.Digest {
            var digest: [UInt8] = .init(repeating: 0, count: Digest.byteCount)
            CC_SHA1_Final(&digest, &self.context)
            return .init(bytes: digest)
        }
    }
}

#endif
