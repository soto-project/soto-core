//
//  HMAC.swift
//  AWSSDKSwift
//
//  Created by Yuki Takei on 2017/03/13.
//
//

import Foundation

#if canImport(CommonCrypto)

import CommonCrypto

func hmac(string: String, key: [UInt8]) -> [UInt8] {
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
