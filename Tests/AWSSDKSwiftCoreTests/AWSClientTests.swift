//
//  AWSClientTests.swift
//  AWSSDKSwiftCoreTests
//
//  Created by Joe Smith on 2018/06/27.
//

import Foundation
import XCTest
@testable import AWSSDKSwiftCore

class AWSClientTests: XCTestCase {
  static var allTests : [(String, (AWSClientTests) -> () throws -> Void)] {
      return [
        ("testJSONMemberParsing", testJSONMemberParsing),
        ("testNestedJSONMemberParsing", testNestedJSONMemberParsing),
      ]
  }

  func testJSONMemberParsing() {
      do {
          var outputDict: [String: Any] = try JSONSerialization.jsonObject(with: IAMResponseModel.listServerCertificates.data(using: .utf8)!, options: []) as? [String: Any] ?? [:]
      } catch {
          XCTFail("\(error)")
          return
      }
  }

  func testNestedJSONMemberParsing() {
  }
}
