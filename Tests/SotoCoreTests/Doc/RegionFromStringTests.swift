//
//  StringRegionTests.swift
//  sotoDevFrameworkTests
//
//  Created by Stormacq, Sebastien on 11/10/2020.
//

import XCTest
import SotoCore

class StringRegionTests: XCTestCase {

    func testStringToRegion() {
            let region = Region(regionName: "eu-west-3")
            XCTAssertNotNil(region)
            XCTAssert(region! == Region.euwest3)
    }

    func testStringToInvalidRegion() {
        XCTAssertNil(Region(regionName: "xxx"))
    }
}
