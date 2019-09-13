//
//  Hash.swift
//  AWSSDKSwift
//
//  Created by Yuki Takei on 2017/03/13.
//
//

import Foundation

#if canImport(CAWSSDKOpenSSL)

import CAWSSDKOpenSSL

public func sha256(_ string: String) -> [UInt8] {
    var bytes = Array(string.utf8)
    return sha256(&bytes)
}

public func sha256(_ bytes: inout [UInt8]) -> [UInt8] {
    var hash = [UInt8](repeating: 0, count: Int(SHA256_DIGEST_LENGTH))
    SHA256(&bytes, bytes.count, &hash)
    return hash
}

public func sha256(_ data: Data) -> [UInt8] {
    return data.withUnsafeBytes { ptr in
        var hash = [UInt8](repeating: 0, count: Int(SHA256_DIGEST_LENGTH))
        if let bytes = ptr.baseAddress?.assumingMemoryBound(to: UInt8.self) {
            SHA256(bytes, data.count, &hash)
        }
        return hash
    }
}

public func sha256(_ bytes1: inout [UInt8], _ bytes2: inout [UInt8]) -> [UInt8] {
    var hash = [UInt8](repeating: 0, count: Int(SHA256_DIGEST_LENGTH))
    var context = SHA256_CTX()
    SHA256_Init(&context)
    SHA256_Update(&context, &bytes1, bytes1.count)
    SHA256_Update(&context, &bytes2, bytes2.count)
    SHA256_Final(&hash, &context)
    return hash
}

public func md5(_ data: Data) -> [UInt8] {
    return data.withUnsafeBytes { ptr in
        var hash = [UInt8](repeating: 0, count: Int(MD5_DIGEST_LENGTH))
        if let bytes = ptr.baseAddress?.assumingMemoryBound(to: UInt8.self) {
            MD5(bytes, data.count, &hash)
        }
        return hash
    }
}

#elseif canImport(CommonCrypto)

import CommonCrypto

public func sha256(_ string: String) -> [UInt8] {
    var bytes = Array(string.utf8)
    return sha256(&bytes)
}

public func sha256(_ bytes: inout [UInt8]) -> [UInt8] {
    var hash = [UInt8](repeating: 0, count: Int(CC_SHA256_DIGEST_LENGTH))
    CC_SHA256(&bytes, CC_LONG(bytes.count), &hash)
    return hash
}

public func sha256(_ data: Data) -> [UInt8] {
    return data.withUnsafeBytes { ptr in
        var hash = [UInt8](repeating: 0, count: Int(CC_SHA256_DIGEST_LENGTH))
        if let bytes = ptr.baseAddress?.assumingMemoryBound(to: UInt8.self) {
            CC_SHA256(bytes, CC_LONG(data.count), &hash)
        }
        return hash
    }
}

public func sha256(_ bytes1: inout [UInt8], _ bytes2: inout [UInt8]) -> [UInt8] {
    var hash = [UInt8](repeating: 0, count: Int(CC_SHA256_DIGEST_LENGTH))
    var context = CC_SHA256_CTX()
    CC_SHA256_Init(&context)
    CC_SHA256_Update(&context, &bytes1, CC_LONG(bytes1.count))
    CC_SHA256_Update(&context, &bytes2, CC_LONG(bytes2.count))
    CC_SHA256_Final(&hash, &context)
    return hash
}

public func md5(_ data: Data) -> [UInt8] {
    return data.withUnsafeBytes { ptr in
        var hash = [UInt8](repeating: 0, count: Int(CC_MD5_DIGEST_LENGTH))
        if let bytes = ptr.baseAddress?.assumingMemoryBound(to: UInt8.self) {
            CC_MD5(bytes, CC_LONG(data.count), &hash)
        }
        return hash
    }
}

#endif
