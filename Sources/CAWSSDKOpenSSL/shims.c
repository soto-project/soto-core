//
//  shims.c
//  AWSSDKSwiftCore
//
//  Created by Adam Fowler on 2019/08/08.
//

// These are functions that shim over differences in different OpenSSL versions,
// which are best handled by using the C preprocessor.
#include "c_awssdk_openssl.h"
#include <string.h>

HMAC_CTX *AWSSDK_HMAC_CTX_new() {
#if OPENSSL_VERSION_NUMBER < 0x10100000L || (defined(LIBRESSL_VERSION_NUMBER) && LIBRESSL_VERSION_NUMBER < 0x2070000fL)
    HMAC_CTX *ctx = OPENSSL_malloc(sizeof(HMAC_CTX));
    if (ctx != NULL) {
        HMAC_CTX_init(ctx);
    }
    return ctx;
#else
    return HMAC_CTX_new();
#endif
}

void AWSSDK_HMAC_CTX_free(HMAC_CTX* ctx) {
#if OPENSSL_VERSION_NUMBER < 0x10100000L || (defined(LIBRESSL_VERSION_NUMBER) && LIBRESSL_VERSION_NUMBER < 0x2070000fL)
    if (ctx != NULL) {
        HMAC_CTX_cleanup(ctx);
        OPENSSL_free(ctx);
    }
#else
    HMAC_CTX_free(ctx);
#endif
}
