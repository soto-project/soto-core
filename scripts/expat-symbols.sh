#!/bin/bash
##===----------------------------------------------------------------------===##
##
## This source file is part of the AWSSDKSwift open source project
##
## Copyright (c) 2020 the AWSSDKSwift project authors
## Licensed under Apache License v2.0
##
## See LICENSE.txt for license information
## See CONTRIBUTORS.txt for the list of AWSSDKSwift project authors
##
## SPDX-License-Identifier: Apache-2.0
##
##===----------------------------------------------------------------------===##

EXPAT_PREFIX_FILE="Sources/CAWSExpat/include/expat_prefix_symbols.h"

# build CAWSExpat
swift build --product CAWSExpat --enable-test-discovery

# get public symbols
find .build/x86_64-apple-macosx/debug/CAWSExpat.build -name "*.o" -exec nm -gUj {} \; > symbols.txt

cat > "$EXPAT_PREFIX_FILE" << "EOF"
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

#ifndef _EXPAT_PREFIX_SYMBOLS_H_
#define _EXPAT_PREFIX_SYMBOLS_H_

#define EXPAT_PREFIX AWS
#define EXPAT_ADD_PREFIX(a, b) a ## _ ## b

EOF

for i in $( cat symbols.txt ); do
    SYMBOL="${i:1}"
    echo "#define $SYMBOL EXPAT_ADD_PREFIX(EXPAT_PREFIX, $SYMBOL)" >> "$EXPAT_PREFIX_FILE"
done

cat >> "$EXPAT_PREFIX_FILE" << "EOF"

#endif // _EXPAT_PREFIX_SYMBOLS_H_
EOF
