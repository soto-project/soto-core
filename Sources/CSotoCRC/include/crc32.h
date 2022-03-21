//===----------------------------------------------------------------------===//
//
// This source file is part of the Soto for AWS open source project
//
// Copyright (c) 2022 the Soto project authors
// Licensed under Apache License v2.0
//
// See LICENSE.txt for license information
// See CONTRIBUTORS.txt for the list of Soto project authors
//
// SPDX-License-Identifier: Apache-2.0
//
//===----------------------------------------------------------------------===//

#include "../zconf.h"

unsigned long soto_crc32(unsigned long crc, const unsigned char FAR *buf, z_size_t len);
unsigned long soto_crc32c(unsigned long crc, const unsigned char FAR *buf, z_size_t len);
