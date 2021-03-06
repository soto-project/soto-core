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

// THIS FILE IS AUTOMATICALLY GENERATED by https://github.com/soto-project/soto-core/scripts/generate-region-tests.swift. DO NOT EDIT.

import SotoCore
import SotoTestUtils
import XCTest

class RegionTests: XCTestCase {
    private func testStringToOneRegion(regionName: String, regionEnum: Region) {
        let region = Region(awsRegionName: regionName)
        XCTAssertNotNil(region)
        XCTAssert(region! == regionEnum)
    }

    func testStringToRegion() {
        self.testStringToOneRegion(regionName: "af-south-1", regionEnum: Region.afsouth1)
        self.testStringToOneRegion(regionName: "ap-east-1", regionEnum: Region.apeast1)
        self.testStringToOneRegion(regionName: "ap-northeast-1", regionEnum: Region.apnortheast1)
        self.testStringToOneRegion(regionName: "ap-northeast-3", regionEnum: Region.apnortheast3)
        self.testStringToOneRegion(regionName: "ap-south-1", regionEnum: Region.apsouth1)
        self.testStringToOneRegion(regionName: "ap-southeast-1", regionEnum: Region.apsoutheast1)
        self.testStringToOneRegion(regionName: "ap-southeast-2", regionEnum: Region.apsoutheast2)
        self.testStringToOneRegion(regionName: "ca-central-1", regionEnum: Region.cacentral1)
        self.testStringToOneRegion(regionName: "cn-northwest-1", regionEnum: Region.cnnorthwest1)
        self.testStringToOneRegion(regionName: "eu-central-1", regionEnum: Region.eucentral1)
        self.testStringToOneRegion(regionName: "eu-north-1", regionEnum: Region.eunorth1)
        self.testStringToOneRegion(regionName: "eu-west-1", regionEnum: Region.euwest1)
        self.testStringToOneRegion(regionName: "eu-west-2", regionEnum: Region.euwest2)
        self.testStringToOneRegion(regionName: "eu-west-3", regionEnum: Region.euwest3)
        self.testStringToOneRegion(regionName: "me-south-1", regionEnum: Region.mesouth1)
        self.testStringToOneRegion(regionName: "sa-east-1", regionEnum: Region.saeast1)
        self.testStringToOneRegion(regionName: "us-east-2", regionEnum: Region.useast2)
        self.testStringToOneRegion(regionName: "us-gov-east-1", regionEnum: Region.usgoveast1)
        self.testStringToOneRegion(regionName: "us-west-1", regionEnum: Region.uswest1)
        self.testStringToOneRegion(regionName: "us-west-2", regionEnum: Region.uswest2)
    }

    func testStringToInvalidRegion() {
        XCTAssertNil(Region(awsRegionName: "xxx"))
    }

    func testRegionEnumRawValue() {
        let region = Region(rawValue: "my-region")
        if Region.other("my-region") == region {
            XCTAssertEqual(region.rawValue, "my-region")
        } else {
            XCTFail("Did not construct Region.other()")
        }
    }

    func testRegionEnumExistingRegion() {
        var region: Region

        region = Region(rawValue: "af-south-1")
        if Region.afsouth1 == region {
            XCTAssertEqual(region.rawValue, "af-south-1")
        } else {
            XCTFail("Did not construct Region(rawValue:) for af-south-1")
        }

        region = Region(rawValue: "ap-east-1")
        if Region.apeast1 == region {
            XCTAssertEqual(region.rawValue, "ap-east-1")
        } else {
            XCTFail("Did not construct Region(rawValue:) for ap-east-1")
        }

        region = Region(rawValue: "ap-northeast-1")
        if Region.apnortheast1 == region {
            XCTAssertEqual(region.rawValue, "ap-northeast-1")
        } else {
            XCTFail("Did not construct Region(rawValue:) for ap-northeast-1")
        }

        region = Region(rawValue: "ap-northeast-3")
        if Region.apnortheast3 == region {
            XCTAssertEqual(region.rawValue, "ap-northeast-3")
        } else {
            XCTFail("Did not construct Region(rawValue:) for ap-northeast-3")
        }

        region = Region(rawValue: "ap-south-1")
        if Region.apsouth1 == region {
            XCTAssertEqual(region.rawValue, "ap-south-1")
        } else {
            XCTFail("Did not construct Region(rawValue:) for ap-south-1")
        }

        region = Region(rawValue: "ap-southeast-1")
        if Region.apsoutheast1 == region {
            XCTAssertEqual(region.rawValue, "ap-southeast-1")
        } else {
            XCTFail("Did not construct Region(rawValue:) for ap-southeast-1")
        }

        region = Region(rawValue: "ap-southeast-2")
        if Region.apsoutheast2 == region {
            XCTAssertEqual(region.rawValue, "ap-southeast-2")
        } else {
            XCTFail("Did not construct Region(rawValue:) for ap-southeast-2")
        }

        region = Region(rawValue: "ca-central-1")
        if Region.cacentral1 == region {
            XCTAssertEqual(region.rawValue, "ca-central-1")
        } else {
            XCTFail("Did not construct Region(rawValue:) for ca-central-1")
        }

        region = Region(rawValue: "cn-northwest-1")
        if Region.cnnorthwest1 == region {
            XCTAssertEqual(region.rawValue, "cn-northwest-1")
        } else {
            XCTFail("Did not construct Region(rawValue:) for cn-northwest-1")
        }

        region = Region(rawValue: "eu-central-1")
        if Region.eucentral1 == region {
            XCTAssertEqual(region.rawValue, "eu-central-1")
        } else {
            XCTFail("Did not construct Region(rawValue:) for eu-central-1")
        }

        region = Region(rawValue: "eu-north-1")
        if Region.eunorth1 == region {
            XCTAssertEqual(region.rawValue, "eu-north-1")
        } else {
            XCTFail("Did not construct Region(rawValue:) for eu-north-1")
        }

        region = Region(rawValue: "eu-west-1")
        if Region.euwest1 == region {
            XCTAssertEqual(region.rawValue, "eu-west-1")
        } else {
            XCTFail("Did not construct Region(rawValue:) for eu-west-1")
        }

        region = Region(rawValue: "eu-west-2")
        if Region.euwest2 == region {
            XCTAssertEqual(region.rawValue, "eu-west-2")
        } else {
            XCTFail("Did not construct Region(rawValue:) for eu-west-2")
        }

        region = Region(rawValue: "eu-west-3")
        if Region.euwest3 == region {
            XCTAssertEqual(region.rawValue, "eu-west-3")
        } else {
            XCTFail("Did not construct Region(rawValue:) for eu-west-3")
        }

        region = Region(rawValue: "me-south-1")
        if Region.mesouth1 == region {
            XCTAssertEqual(region.rawValue, "me-south-1")
        } else {
            XCTFail("Did not construct Region(rawValue:) for me-south-1")
        }

        region = Region(rawValue: "sa-east-1")
        if Region.saeast1 == region {
            XCTAssertEqual(region.rawValue, "sa-east-1")
        } else {
            XCTFail("Did not construct Region(rawValue:) for sa-east-1")
        }

        region = Region(rawValue: "us-east-2")
        if Region.useast2 == region {
            XCTAssertEqual(region.rawValue, "us-east-2")
        } else {
            XCTFail("Did not construct Region(rawValue:) for us-east-2")
        }

        region = Region(rawValue: "us-gov-east-1")
        if Region.usgoveast1 == region {
            XCTAssertEqual(region.rawValue, "us-gov-east-1")
        } else {
            XCTFail("Did not construct Region(rawValue:) for us-gov-east-1")
        }

        region = Region(rawValue: "us-west-1")
        if Region.uswest1 == region {
            XCTAssertEqual(region.rawValue, "us-west-1")
        } else {
            XCTFail("Did not construct Region(rawValue:) for us-west-1")
        }

        region = Region(rawValue: "us-west-2")
        if Region.uswest2 == region {
            XCTAssertEqual(region.rawValue, "us-west-2")
        } else {
            XCTFail("Did not construct Region(rawValue:) for us-west-2")
        }
    }
}
