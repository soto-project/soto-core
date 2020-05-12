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

import XCTest
@testable import AWSSDKSwiftCoreTests
@testable import AWSSignerTests

XCTMain([
    testCase(AsyncHTTPClientTests.allTests),
    testCase(AWSClientTests.allTests),
    testCase(CredentialTests.allTests),
    testCase(DictionaryEncoderTests.allTests),
    testCase(JSONCoderTests.allTests),
    testCase(MetaDataServiceTests.allTests),
    testCase(PaginateTests.allTests),
    testCase(PerformanceTests.allTests),
    testCase(QueryEncoderTests.allTests),
    testCase(TimeStampTests.allTests),
    testCase(ValidationTests.allTests),
    testCase(XMLCoderTests.allTests),
    testCase(XMLTests.allTests),
    testCase(AWSSignerTests.allTests)
])
