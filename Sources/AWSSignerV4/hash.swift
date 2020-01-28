//
//  hash.swift
//  AsyncHTTPClient
//
//  Created by Adam Fowler on 2019/08/29.
//

import Foundation

#if canImport(CommonCrypto)

import CommonCrypto

/// Calculate SHA256 of array of bytes
public func sha256(_ bytes: [UInt8]) -> [UInt8] {
    var hash = [UInt8](repeating: 0, count: Int(CC_SHA256_DIGEST_LENGTH))
    CC_SHA256(bytes, CC_LONG(bytes.count), &hash)
    return hash
}

/// Calculate SHA256 of buffer
public func sha256(_ buffer: UnsafeBufferPointer<UInt8>) -> [UInt8] {
    var hash = [UInt8](repeating: 0, count: Int(CC_SHA256_DIGEST_LENGTH))
    CC_SHA256(buffer.baseAddress, CC_LONG(buffer.count), &hash)
    return hash
}

/// Init SHA256 Context
public func sha256_Init() -> CC_SHA256_CTX {
    var context = CC_SHA256_CTX()
    CC_SHA256_Init(&context)
    return context
}

/// Update SHA256 Context
public func sha256_Update(_ context: inout CC_SHA256_CTX, _ bytes: [UInt8]) {
    CC_SHA256_Update(&context, bytes, CC_LONG(bytes.count))
}

/// Update SHA256 Context
public func sha256_Update(_ context: inout CC_SHA256_CTX, _ buffer: UnsafeBufferPointer<UInt8>) {
    CC_SHA256_Update(&context, buffer.baseAddress, CC_LONG(buffer.count))
}

/// Finalize the SHA256 Context and return the hash
public func sha256_Final(_ context: inout CC_SHA256_CTX) -> [UInt8] {
    var hash = [UInt8](repeating: 0, count: Int(CC_SHA256_DIGEST_LENGTH))
    CC_SHA256_Final(&hash, &context)
    return hash
}

/// Calculate HMAC of string, with key
public func hmac(string: String, key: [UInt8]) -> [UInt8] {
    var context = CCHmacContext()
    CCHmacInit(&context, CCHmacAlgorithm(kCCHmacAlgSHA256), key, key.count)
    
    let bytes = Array(string.utf8)
    CCHmacUpdate(&context, bytes, bytes.count)
    var digest = [UInt8](repeating: 0, count: Int(CC_SHA256_DIGEST_LENGTH))
    CCHmacFinal(&context, &digest)
    
    return digest
}

/// Calculate MD5 of buffer
public func md5(_ buffer: UnsafeBufferPointer<UInt8>) -> [UInt8] {
    var hash = [UInt8](repeating: 0, count: Int(CC_MD5_DIGEST_LENGTH))
    CC_MD5(buffer.baseAddress, CC_LONG(buffer.count), &hash)
    return hash
}

#elseif canImport(CAWSSDKOpenSSL)

import CAWSSDKOpenSSL

/// :nodoc: Calculate SHA256 of array of bytes
public func sha256(_ bytes: [UInt8]) -> [UInt8] {
    var hash = [UInt8](repeating: 0, count: Int(SHA256_DIGEST_LENGTH))
    SHA256(bytes, bytes.count, &hash)
    return hash
}

/// :nodoc: Calculate SHA256 of buffer
public func sha256(_ buffer: UnsafeBufferPointer<UInt8>) -> [UInt8] {
    var hash = [UInt8](repeating: 0, count: Int(SHA256_DIGEST_LENGTH))
    SHA256(buffer.baseAddress, buffer.count, &hash)
    return hash
}

/// :nodoc: Init SHA256 Context
public func sha256_Init() -> SHA256_CTX {
    var context = SHA256_CTX()
    SHA256_Init(&context)
    return context
}

/// :nodoc: Update SHA256 Context
public func sha256_Update(_ context: inout SHA256_CTX, _ bytes: [UInt8]) {
    SHA256_Update(&context, bytes, bytes.count)
}

/// :nodoc: Update SHA256 Context
public func sha256_Update(_ context: inout SHA256_CTX, _ buffer: UnsafeBufferPointer<UInt8>) {
    SHA256_Update(&context, buffer.baseAddress, buffer.count)
}

/// :nodoc: Finalize the SHA256 Context and return the hash
public func sha256_Final(_ context: inout SHA256_CTX) -> [UInt8] {
    var hash = [UInt8](repeating: 0, count: Int(SHA256_DIGEST_LENGTH))
    SHA256_Final(&hash, &context)
    return hash
}

/// :nodoc: Calculate HMAC of string, with key
func hmac(string: String, key: [UInt8]) -> [UInt8] {
    let context = AWSSDK_HMAC_CTX_new()
    HMAC_Init_ex(context, key, Int32(key.count), EVP_sha256(), nil)
    
    let bytes = Array(string.utf8)
    HMAC_Update(context, bytes, bytes.count)
    var digest = [UInt8](repeating: 0, count: Int(EVP_MAX_MD_SIZE))
    var length: UInt32 = 0
    HMAC_Final(context, &digest, &length)
    AWSSDK_HMAC_CTX_free(context)
    
    return Array(digest[0..<Int(length)])
}

/// Calculate MD5 of buffer
public func md5(_ buffer: UnsafeBufferPointer<UInt8>) -> [UInt8] {
    var hash = [UInt8](repeating: 0, count: Int(MD5_DIGEST_LENGTH))
    MD5(buffer.baseAddress, buffer.count, &hash)
    return hash
}

#endif

/// Calculate SHA256 of string
public func sha256(_ string: String) -> [UInt8] {
    return string.utf8.withContiguousStorageIfAvailable { bytes in
        return sha256(bytes)
    }! // UTF8View will return a value, so can force unwrap
}

/// Calculate SHA256 of buffer
public func sha256(_ data: Data) -> [UInt8] {
    return data.withUnsafeBytes { bytes in
        return sha256(bytes.bindMemory(to: UInt8.self))
    }
}

// Calculate SHA256 of two byte arrays
public func sha256(_ bytes1: inout [UInt8], _ bytes2: inout [UInt8]) -> [UInt8] {
    var context = sha256_Init()
    sha256_Update(&context, bytes1)
    sha256_Update(&context, bytes2)
    return sha256_Final(&context)
}

