//
//  MetaDataServiceTests.swift
//  AWSSDKSwiftCoreTests
//
//  Created by Jonathan McAllister on 2017/12/29.
//

import Foundation
import XCTest
@testable import AWSSDKSwiftCore

class MetaDataServiceTests: XCTestCase {
  static var allTests : [(String, (MetaDataServiceTests) -> () throws -> Void)] {
      return [
        ("testMetaDataServiceForECSCredentials", testMetaDataServiceForECSCredentials),
        ("testMetaDataServiceForInstanceProfileCredentials", testMetaDataServiceForInstanceProfileCredentials)
      ]
  }

  override func tearDown() {
    MetaDataService.containerCredentialsUri = nil
  }

  func testMetaDataServiceForECSCredentials() {
    MetaDataService.containerCredentialsUri = "/v2/credentials/5275a487-9ff6-49b7-b50c-b64850f99999"

    do {
       let body: [String: String] = ["RoleArn" : "arn:aws:iam::111222333444:role/mytask",
                                     "AccessKeyId" : "ABCDEABCJOXYK7TPHCHTRKAA",
                                     "SecretAccessKey" : "X+9PUEvV/xS2a7xQTg",
                                     "Token" : "XYZ123dzENH//////////",
                                     "Expiration" : "2017-12-30T13:22:39Z"]

       let encodedData = try JSONEncoder().encode(body)
       let metaData = try JSONDecoder().decode(MetaDataService.MetaData.self, from: encodedData)

       XCTAssertEqual(metaData.credential.accessKeyId, "ABCDEABCJOXYK7TPHCHTRKAA")

       let host = MetaDataService.serviceProvider.host
       XCTAssertEqual(host , "169.254.170.2")

       let baseURLString = MetaDataService.serviceProvider.baseURLString
       XCTAssertEqual(baseURLString, "http://169.254.170.2/v2/credentials/5275a487-9ff6-49b7-b50c-b64850f99999")

       do {
           let uri = try MetaDataService.serviceProvider.uri()
           XCTAssertEqual(uri, "/v2/credentials/5275a487-9ff6-49b7-b50c-b64850f99999")
       } catch {
           XCTFail("\(error)")
           return
       }
    } catch {
        XCTFail("\(error)")
        return
    }
  }

  func testMetaDataServiceForInstanceProfileCredentials() {
    do {
       let body: [String: String] = ["Code" : "Success",
                                     "LastUpdated" : "2018-01-05T05:25:41Z",
                                     "Type" : "AWS-HMAC",
                                     "AccessKeyId" : "XYZABCJOXYK7TPHCHTRKAA",
                                     "SecretAccessKey" : "X+9PUEvV/xS2a7xQTg",
                                     "Token" : "XYZ123dzENH//////////",
                                     "Expiration" : "2017-12-30T13:22:39Z"]

       let encodedData = try JSONEncoder().encode(body)
       let metaData = try JSONDecoder().decode(MetaDataService.MetaData.self, from: encodedData)

       XCTAssertEqual(metaData.credential.accessKeyId, "XYZABCJOXYK7TPHCHTRKAA")

       let host = MetaDataService.serviceProvider.host
       XCTAssertEqual(host, "169.254.169.254")

       let baseURLString = MetaDataService.serviceProvider.baseURLString
       XCTAssertEqual(baseURLString, "http://169.254.169.254/latest/meta-data/iam/security-credentials/")
    } catch {
        XCTFail("\(error)")
        return
    }
  }
}
