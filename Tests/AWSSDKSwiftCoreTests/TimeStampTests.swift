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

    func testDecodeISOFromJSON() {
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
    
    func testDecodeISOFromXML() {
        do {
            let xml = "<A><date>2017-01-01T00:01:00.000Z</date></A>"
            let xmlElement = try XML.Element(xmlString: xml)
            let a = try XMLDecoder().decode(A.self, from: xmlElement)
            XCTAssertEqual(a.date.stringValue, "2017-01-01T00:01:00.000Z")
        } catch {
            XCTFail("\(error)")
        }
    }
    
    func testDecodeHttpFormattedTimestamp() {
        do {
            let xml = "<A><date>Tue, 15 Nov 1994 12:45:26 GMT</date></A>"
            let xmlElement = try XML.Element(xmlString: xml)
            let a = try XMLDecoder().decode(A.self, from: xmlElement)
            XCTAssertEqual(a.date.stringValue, "1994-11-15T12:45:26.000Z")
        } catch {
            XCTFail("\(error)")
        }

    }
    
    func testDecodeUnixEpochTimestamp() {
        do {
            let xml = "<A><date>1221382800</date></A>"
            let xmlElement = try XML.Element(xmlString: xml)
            let a = try XMLDecoder().decode(A.self, from: xmlElement)
            XCTAssertEqual(a.date.stringValue, "2008-09-14T09:00:00.000Z")
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
            ("testDecodeISOFromJSON", testDecodeISOFromJSON),
            ("testDecodeISOFromXML", testDecodeISOFromXML),
            ("testEncodeToJSON", testEncodeToJSON),
        ]
    }
}
