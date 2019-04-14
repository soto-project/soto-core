//
//  HMAC.swift
//  AWSSDKSwift
//
//  Created by Yuki Takei on 2017/03/13.
//
//

import Foundation
import CNIOBoringSSL

func hmac(string: String, key: [UInt8]) -> [UInt8] {
    var context = HMAC_CTX()
    CNIOBoringSSL_HMAC_Init_ex(&context, key, key.count, CNIOBoringSSL_EVP_sha256(), nil)

    let bytes = Array(string.utf8)
    CNIOBoringSSL_HMAC_Update(&context, bytes, bytes.count)
    var digest = [UInt8](repeating: 0, count: Int(EVP_MAX_MD_SIZE))
    var length: UInt32 = 0
    CNIOBoringSSL_HMAC_Final(&context, &digest, &length)
    CNIOBoringSSL_HMAC_CTX_cleanup(&context)

    return Array(digest[0..<Int(length)])
}
