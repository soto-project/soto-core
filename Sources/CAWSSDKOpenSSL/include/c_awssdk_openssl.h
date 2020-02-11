//
//  c_awssdk_openssl.h
//  AWSSDKSwiftCore
//
//  Created by Adam Fowler on 2019/08/08.
//

#ifndef C_AWSSDK_OPENSSL_H
#define C_AWSSDK_OPENSSL_H

#ifdef __linux__

#include <openssl/hmac.h>
#include <openssl/md5.h>
#include <openssl/sha.h>

HMAC_CTX *AWSSDK_HMAC_CTX_new();
void AWSSDK_HMAC_CTX_free(HMAC_CTX* ctx);

#endif // __linux__


#endif // C_AWSSDK_OPENSSL_H
