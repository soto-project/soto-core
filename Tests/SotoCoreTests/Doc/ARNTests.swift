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

import SotoCore
import Testing

#if compiler(>=6.0)
struct ARNTests {
    @Test
    func testValidARNWithoutResourceType() throws {
        let arn = try #require(ARN(string: "arn:aws:sns:us-east-1:123456789012:example-sns-topic-name"))
        #expect(arn.partition == .aws)
        #expect(arn.service == "sns")
        #expect(arn.region == .useast1)
        #expect(arn.accountId == "123456789012")
        #expect(arn.resourceId == "example-sns-topic-name")
        #expect(arn.resourceType == nil)
    }

    @Test(arguments: [
        "arn:aws:ec2:us-west-1:123456789012:vpc/vpc-0e9801d129EXAMPLE",
        "arn:aws:ec2:us-west-1:123456789012:vpc:vpc-0e9801d129EXAMPLE",
    ])
    func testValidARNWithoutWithResourceType(arnString: String) throws {
        let arn = try #require(ARN(string: arnString))
        #expect(arn.partition == .aws)
        #expect(arn.service == "ec2")
        #expect(arn.region == .uswest1)
        #expect(arn.accountId == "123456789012")
        #expect(arn.resourceId == "vpc-0e9801d129EXAMPLE")
        #expect(arn.resourceType == "vpc")
    }

    @Test
    func testValidARNWithoutRegion() throws {
        let arn = try #require(ARN(string: "arn:aws:iam::123456789012:user/adam"))
        #expect(arn.partition == .aws)
        #expect(arn.service == "iam")
        #expect(arn.region == nil)
        #expect(arn.accountId == "123456789012")
        #expect(arn.resourceId == "adam")
        #expect(arn.resourceType == "user")
    }

    @Test
    func testValidARNWithoutAccountID() throws {
        let arn = try #require(ARN(string: "arn:aws:s3:::my_corporate_bucket/*"))
        #expect(arn.partition == .aws)
        #expect(arn.service == "s3")
        #expect(arn.region == nil)
        #expect(arn.accountId == nil)
        #expect(arn.resourceId == "*")
        #expect(arn.resourceType == "my_corporate_bucket")
    }

}
#endif
