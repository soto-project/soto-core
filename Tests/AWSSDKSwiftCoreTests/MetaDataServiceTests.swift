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
    MetaDataService.container_credentials_uri = nil
  }

  func testMetaDataServiceForECSCredentials() {
    MetaDataService.container_credentials_uri = "/v2/credentials/5275a487-9ff6-49b7-b50c-b64850f99999"
  
    do {
       let body: [String: Any] = ["RoleArn" : "arn:aws:iam::111222333444:role/mytask",
                                  "AccessKeyId" : "ABCDEABCJOXYK7TPHCHTRKAA",
                                  "SecretAccessKey" : "X+9PUEvV/xS2a7xQTg",
                                  "Token" : "XYZ123dzENH//////////",
                                  "Expiration" : "2017-12-30T13:22:39Z"]
  
       let metadata = try MetaDataService.MetaData(dictionary: body)
       XCTAssertEqual(metadata.credential.accessKeyId, "ABCDEABCJOXYK7TPHCHTRKAA")
  
       let url = try MetaDataService.serviceHost.url()
       guard let host = url.host else {
         XCTFail("Error: host should not be nil")
         return
       }
       XCTAssertEqual(host, "169.254.170.2")
       XCTAssertEqual(url.path, "/v2/credentials/5275a487-9ff6-49b7-b50c-b64850f99999")
    } catch {
        XCTFail("\(error)")
        return
    }
  }
  
  func testMetaDataServiceForInstanceProfileCredentials() { 
    do {
       let body: [String: Any] = ["Code" : "Success",
                                  "LastUpdated" : "2018-01-05T05:25:41Z",
                                  "Type" : "AWS-HMAC",
                                  "AccessKeyId" : "XYZABCJOXYK7TPHCHTRKAA",
                                  "SecretAccessKey" : "X+9PUEvV/xS2a7xQTg",
                                  "Token" : "XYZ123dzENH//////////",
                                  "Expiration" : "2017-12-30T13:22:39Z"]

       let metadata = try MetaDataService.MetaData(dictionary: body)
       XCTAssertEqual(metadata.credential.accessKeyId, "XYZABCJOXYK7TPHCHTRKAA")
       
       let baseURLString = MetaDataService.serviceHost.baseURLString
       XCTAssertEqual(baseURLString, "http://169.254.169.254/latest/meta-data/iam/security-credentials/")
    } catch {
        XCTFail("\(error)")
        return
    }
  }
}
