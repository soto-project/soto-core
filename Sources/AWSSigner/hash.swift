//
//  hash.swift
//  AsyncHTTPClient
//
//  Created by Adam Fowler on 2019/08/29.
//

import Foundation

#if canImport(CommonCrypto)

import CommonCrypto

public func sha256(_ string: String) -> [UInt8] {
    let bytes = Array(string.utf8)
    return sha256(bytes)
}

public func sha256(_ bytes: [UInt8]) -> [UInt8] {
    var hash = [UInt8](repeating: 0, count: Int(CC_SHA256_DIGEST_LENGTH))
    CC_SHA256(bytes, CC_LONG(bytes.count), &hash)
    return hash
}

public func sha256(_ buffer: UnsafeBufferPointer<UInt8>) -> [UInt8] {
    var hash = [UInt8](repeating: 0, count: Int(CC_SHA256_DIGEST_LENGTH))
    CC_SHA256(buffer.baseAddress, CC_LONG(buffer.count), &hash)
    return hash
}

public func hmac(string: String, key: [UInt8]) -> [UInt8] {
    var context = CCHmacContext()
    CCHmacInit(&context, CCHmacAlgorithm(kCCHmacAlgSHA256), key, key.count)
    
    let bytes = Array(string.utf8)
    CCHmacUpdate(&context, bytes, bytes.count)
    var digest = [UInt8](repeating: 0, count: Int(CC_SHA256_DIGEST_LENGTH))
    CCHmacFinal(&context, &digest)
    
    return digest
}

#elseif canImport(CAWSSDKOpenSSL)

import CAWSSDKOpenSSL

public func sha256(_ string: String) -> [UInt8] {
    let bytes = Array(string.utf8)
    return sha256(bytes)
}

public func sha256(_ bytes: [UInt8]) -> [UInt8] {
    var hash = [UInt8](repeating: 0, count: Int(SHA256_DIGEST_LENGTH))
    SHA256(bytes, bytes.count, &hash)
    return hash
}

public func sha256(_ buffer: UnsafeBufferPointer<UInt8>) -> [UInt8] {
    var hash = [UInt8](repeating: 0, count: Int(SHA256_DIGEST_LENGTH))
    SHA256(buffer.baseAddress, buffer.count, &hash)
    return hash
}

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

#endif
