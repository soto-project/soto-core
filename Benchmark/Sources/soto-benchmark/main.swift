//===----------------------------------------------------------------------===//
//
// This source file is part of the Soto for AWS open source project
//
// Copyright (c) 2017-2020 the Soto project authors
// Licensed under Apache License v2.0
//
// See LICENSE.txt for license information
// See CONTRIBUTORS.txt for the list of Soto project authors
//
// SPDX-License-Identifier: Apache-2.0
//
//===----------------------------------------------------------------------===//

import Benchmark

let suites = [
    awsSignerV4Suite,
    queryEncoderSuite,
    xmlEncoderSuite,
    xmlDecoderSuite,
    dictionaryDecoderSuite,
    awsClientSuite,
]

Benchmark.main(suites)
