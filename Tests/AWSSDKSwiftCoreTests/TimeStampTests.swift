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
import AWSTestUtils
import AWSXML
@testable import AWSSDKSwiftCore

class TimeStampTests: XCTestCase {

    struct A: Codable {
        let date: TimeStamp
    }

    func testDecodeISOFromJSON() {
        do {
            struct A: Codable {
                let date: TimeStamp
            }
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
            struct A: Codable {
                @Coding<ISO8601TimeStampCoder> var date: TimeStamp
            }
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
            struct A: Codable {
                let date: TimeStamp
            }
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
            struct A: Codable {
                let date: TimeStamp
            }
            let xml = "<A><date>1221382800</date></A>"
            let xmlElement = try XML.Element(xmlString: xml)
            let a = try XMLDecoder().decode(A.self, from: xmlElement)
            XCTAssertEqual(a.date.stringValue, "2008-09-14T09:00:00.000Z")
        } catch {
            XCTFail("\(error)")
        }
    }
    
    func testEncodeISO8601ToXML() {
        do {
            struct A: Codable {
                @Coding<ISO8601TimeStampCoder> var date: TimeStamp
            }
            let a = A(date: TimeStamp("2019-05-01T00:00:00.001Z")!)
            let xml = try XMLEncoder().encode(a)
            XCTAssertEqual(xml.xmlString, "<A><date>2019-05-01T00:00:00.001Z</date></A>")
        } catch {
            XCTFail("\(error)")
        }
    }

    func testEncodeHTTPHeaderToJSON() {
        do {
            struct A: AWSEncodableShape {
                @Coding<HTTPHeaderTimeStampCoder> var date: TimeStamp
            }
            let a = A(date: TimeStamp("2019-05-01T00:00:00.001Z")!)
            let client = createAWSClient()
            let request = try client.createAWSRequest(operation: "test", path: "/", httpMethod: "GET", input: a)
            XCTAssertEqual(request.body.asString(), "{\"date\":\"Wed, 1 May 2019 00:00:00 GMT\"}")
        } catch {
            XCTFail("\(error)")
        }
    }

    func testEncodeUnixEpochToJSON() {
        do {
            struct A: Codable {
                @Coding<UnixEpochTimeStampCoder> var date: TimeStamp
            }
            let a = A(date: TimeStamp(23983978378))
            let data = try JSONEncoder().encode(a)
            let jsonString = String(data: data, encoding: .utf8)
            XCTAssertEqual(jsonString, "{\"date\":23983978378}")
        } catch {
            XCTFail("\(error)")
        }
    }
}
