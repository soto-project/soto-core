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

import CommonCrypto

public struct SHA256Digest : ByteDigest {
    public static var byteCount: Int { return Int(CC_SHA256_DIGEST_LENGTH) }
    public var bytes: [UInt8]
}

public struct SHA256: CCHashFunction {
    public typealias Digest = SHA256Digest
    public static var algorithm: CCHmacAlgorithm { return CCHmacAlgorithm(kCCHmacAlgSHA256) }
    var context: CC_SHA256_CTX

    public static func hash(bufferPointer: UnsafeRawBufferPointer) -> Self.Digest {
        var digest: [UInt8] = .init(repeating: 0, count: Digest.byteCount)
        CC_SHA256(bufferPointer.baseAddress, CC_LONG(bufferPointer.count), &digest)
        return .init(bytes: digest)
    }

    public init() {
        context = CC_SHA256_CTX()
        CC_SHA256_Init(&context)
    }
    
    public mutating func update(bufferPointer: UnsafeRawBufferPointer) {
        CC_SHA256_Update(&context, bufferPointer.baseAddress, CC_LONG(bufferPointer.count))
    }
    
    public mutating func finalize() -> Self.Digest {
        var digest: [UInt8] = .init(repeating: 0, count: Digest.byteCount)
        CC_SHA256_Final(&digest, &context)
        return .init(bytes: digest)
    }
}

public struct SHA384Digest : ByteDigest {
    public static var byteCount: Int { return Int(CC_SHA384_DIGEST_LENGTH) }
    public var bytes: [UInt8]
}

public struct SHA384: CCHashFunction {
    public typealias Digest = SHA384Digest
    public static var algorithm: CCHmacAlgorithm { return CCHmacAlgorithm(kCCHmacAlgSHA384) }
    var context: CC_SHA512_CTX

    public static func hash(bufferPointer: UnsafeRawBufferPointer) -> Self.Digest {
        var digest: [UInt8] = .init(repeating: 0, count: Digest.byteCount)
        CC_SHA384(bufferPointer.baseAddress, CC_LONG(bufferPointer.count), &digest)
        return .init(bytes: digest)
    }

    public init() {
        context = CC_SHA512_CTX()
        CC_SHA384_Init(&context)
    }
    
    public mutating func update(bufferPointer: UnsafeRawBufferPointer) {
        CC_SHA384_Update(&context, bufferPointer.baseAddress, CC_LONG(bufferPointer.count))
    }
    
    public mutating func finalize() -> Self.Digest {
        var digest: [UInt8] = .init(repeating: 0, count: Digest.byteCount)
        CC_SHA384_Final(&digest, &context)
        return .init(bytes: digest)
    }
}

public struct SHA512Digest : ByteDigest {
    public static var byteCount: Int { return Int(CC_SHA512_DIGEST_LENGTH) }
    public var bytes: [UInt8]
}

public struct SHA512: CCHashFunction {
    public typealias Digest = SHA512Digest
    public static var algorithm: CCHmacAlgorithm { return CCHmacAlgorithm(kCCHmacAlgSHA512) }
    var context: CC_SHA512_CTX

    public static func hash(bufferPointer: UnsafeRawBufferPointer) -> Self.Digest {
        var digest: [UInt8] = .init(repeating: 0, count: Digest.byteCount)
        CC_SHA512(bufferPointer.baseAddress, CC_LONG(bufferPointer.count), &digest)
        return .init(bytes: digest)
    }

    public init() {
        context = CC_SHA512_CTX()
        CC_SHA512_Init(&context)
    }
    
    public mutating func update(bufferPointer: UnsafeRawBufferPointer) {
        CC_SHA512_Update(&context, bufferPointer.baseAddress, CC_LONG(bufferPointer.count))
    }
    
    public mutating func finalize() -> Self.Digest {
        var digest: [UInt8] = .init(repeating: 0, count: Digest.byteCount)
        CC_SHA512_Final(&digest, &context)
        return .init(bytes: digest)
    }
}

#endif
