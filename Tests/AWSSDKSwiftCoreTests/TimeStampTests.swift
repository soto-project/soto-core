//
//  TimeStampTests.swift
//  AWSSDKSwiftCoreTests
//
//  Created by Yuki Takei on 2017/10/09.
//

import Foundation
import XCTest
@testable import AWSSDKSwiftCore

class TimeStampTests: XCTestCase {

    struct A: Codable {
        let date: TimeStamp
    }

    func testDecodeFromJSON() {
        do {
            let json = "{\"date\": \"2017-01-01T00:00:00.000Z\"}"
            if let json_data = json.data(using: .utf8) {
                let a = try JSONDecoder().decode(A.self, from: json_data)
                XCTAssertEqual(a.date.stringValue, "2017-01-01T00:00:00.000Z")
            } else {
                XCTFail("Failed to read JSON")
            }
        } catch {
            XCTFail("\(error)")
        }
    }
    
    func testDecodeFromXML() {
        do {
            let xml = "<A><date>2017-01-01T00:01:00.000Z</date></A>"
            let xmlElement = try XML.Element(xmlString: xml)
            let a = try XMLDecoder().decode(A.self, from: xmlElement)
            XCTAssertEqual(a.date.stringValue, "2017-01-01T00:01:00.000Z")
        } catch {
            XCTFail("\(error)")
        }
    }
    
    func testEncodeToJSON() {
        do {
            let a = A(date: TimeStamp("2019-05-01T00:00:00.001Z"))
            let data = try JSONEncoder().encode(a)
            let jsonString = String(data: data, encoding: .utf8)
            XCTAssertEqual(jsonString, "{\"date\":\"2019-05-01T00:00:00.001Z\"}")
        } catch {
            XCTFail("\(error)")
        }
    }

    static var allTests : [(String, (TimeStampTests) -> () throws -> Void)] {
        return [
            ("testDecodeFromJSON", testDecodeFromJSON),
            ("testDecodeFromXML", testDecodeFromXML),
            ("testEncodeToJSON", testEncodeToJSON),
        ]
    }
}
