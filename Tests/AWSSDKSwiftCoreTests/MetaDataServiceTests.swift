//
//  MetaDataServiceTests.swift
//  AWSSDKSwiftCoreTests
//
//  Created by Jonathan McAllister on 2017/12/29.
//

import XCTest
@testable import AWSSDKSwiftCore

class MetaDataServiceTests: XCTestCase {
    static var allTests : [(String, (MetaDataServiceTests) -> () throws -> Void)] {
        return [
            ("testInstanceMetaDataService", testInstanceMetaDataService),
            ("testInstanceMetaDataServiceFail", testInstanceMetaDataServiceFail),
        ]
    }

    func testInstanceMetaDataService() {
        let body: [String: String] = ["Code" : "Success",
                                      "LastUpdated" : "2018-01-05T05:25:41Z",
                                      "Type" : "AWS-HMAC",
                                      "AccessKeyId" : "XYZABCJOXYK7TPHCHTRKAA",
                                      "SecretAccessKey" : "X+9PUEvV/xS2a7xQTg",
                                      "Token" : "XYZ123dzENH//////////",
                                      "Expiration" : "2017-12-30T13:22:39Z"]

        do {
            let encodedData = try JSONEncoder().encode(body)
            let instanceMetaData = InstanceMetaDataServiceProvider()
            let credential = instanceMetaData.decodeCredential(encodedData)

            XCTAssertNotNil(credential)
            XCTAssertEqual(credential?.accessKeyId, "XYZABCJOXYK7TPHCHTRKAA")
            XCTAssertEqual(credential?.secretAccessKey, "X+9PUEvV/xS2a7xQTg")
            XCTAssertEqual(credential?.sessionToken, "XYZ123dzENH//////////")
        } catch {
            XCTFail(error.localizedDescription)
        }
    }

    func testInstanceMetaDataServiceFail() {
        // removed "Code" entry
        let body: [String: String] = ["LastUpdated" : "2018-01-05T05:25:41Z",
                                      "Type" : "AWS-HMAC",
                                      "AccessKeyId" : "XYZABCJOXYK7TPHCHTRKAA",
                                      "SecretAccessKey" : "X+9PUEvV/xS2a7xQTg",
                                      "Token" : "XYZ123dzENH//////////",
                                      "Expiration" : "2017-12-30T13:22:39Z"]

        do {
            let encodedData = try JSONEncoder().encode(body)
            let instanceMetaData = InstanceMetaDataServiceProvider()
            let credential = instanceMetaData.decodeCredential(encodedData)
            XCTAssertNil(credential)
        } catch {
            XCTFail(error.localizedDescription)
        }
    }
}
