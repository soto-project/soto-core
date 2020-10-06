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

@testable import SotoCore
import SotoTestUtils
import SotoXML
import XCTest

class TimeStampTests: XCTestCase {
    private let dateFormatter: DateFormatter = {
        let dateFormatter = DateFormatter()
        dateFormatter.locale = Locale(identifier: "en_US_POSIX")
        dateFormatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSS'Z'"
        dateFormatter.timeZone = TimeZone(secondsFromGMT: 0)
        return dateFormatter
    }()
    
    struct A: Codable {
        let date: Date
    }

    func testDecodeJSON() {
        do {
            struct A: Codable {
                let date: Date
            }
            let json = "{\"date\": 234876345}"
            if let json_data = json.data(using: .utf8) {
                let a = try JSONDecoder().decode(A.self, from: json_data)
                XCTAssertEqual(a.date.timeIntervalSince1970, 234_876_345)
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
                @CustomCoding<ISO8601DateCoder> var date: Date
            }
            let xml = "<A><date>2017-01-01T00:01:00.000Z</date></A>"
            let xmlElement = try XML.Element(xmlString: xml)
            let a = try XMLDecoder().decode(A.self, from: xmlElement)
            XCTAssertEqual(dateFormatter.string(from: a.date), "2017-01-01T00:01:00.000Z")
        } catch {
            XCTFail("\(error)")
        }
    }

    func testDecodeISONoMillisecondFromXML() {
        do {
            struct A: Codable {
                @CustomCoding<ISO8601DateCoder> var date: Date
            }
            let xml = "<A><date>2017-01-01T00:01:00Z</date></A>"
            let xmlElement = try XML.Element(xmlString: xml)
            let a = try XMLDecoder().decode(A.self, from: xmlElement)
            XCTAssertEqual(dateFormatter.string(from: a.date), "2017-01-01T00:01:00.000Z")
        } catch {
            XCTFail("\(error)")
        }
    }

    func testDecodeHttpFormattedTimestamp() {
        do {
            struct A: Codable {
                @CustomCoding<HTTPHeaderDateCoder> var date: Date
            }
            let xml = "<A><date>Tue, 15 Nov 1994 12:45:26 GMT</date></A>"
            let xmlElement = try XML.Element(xmlString: xml)
            let a = try XMLDecoder().decode(A.self, from: xmlElement)
            XCTAssertEqual(dateFormatter.string(from: a.date), "1994-11-15T12:45:26.000Z")
        } catch {
            XCTFail("\(error)")
        }
    }

    func testDecodeUnixEpochTimestamp() {
        do {
            struct A: Codable {
                let date: Date
            }
            let xml = "<A><date>1221382800</date></A>"
            let xmlElement = try XML.Element(xmlString: xml)
            let a = try XMLDecoder().decode(A.self, from: xmlElement)
            XCTAssertEqual(dateFormatter.string(from: a.date), "2008-09-14T09:00:00.000Z")
        } catch {
            XCTFail("\(error)")
        }
    }

    func testEncodeISO8601ToXML() {
        do {
            struct A: Codable {
                @CustomCoding<ISO8601DateCoder> var date: Date
            }
            let a = A(date: dateFormatter.date(from: "2019-05-01T00:00:00.001Z")!)
            let xml = try XMLEncoder().encode(a)
            XCTAssertEqual(xml.xmlString, "<A><date>2019-05-01T00:00:00.001Z</date></A>")
        } catch {
            XCTFail("\(error)")
        }
    }

    func testEncodeHTTPHeaderToJSON() {
        struct A: AWSEncodableShape {
            @CustomCoding<HTTPHeaderDateCoder> var date: Date
        }
        let a = A(date: dateFormatter.date(from: "2019-05-01T00:00:00.001Z")!)
        let config = createServiceConfig()

        var request: AWSRequest?
        XCTAssertNoThrow(request = try AWSRequest(operation: "test", path: "/", httpMethod: .GET, input: a, configuration: config))
        XCTAssertEqual(request?.body.asString(), "{\"date\":\"Wed, 1 May 2019 00:00:00 GMT\"}")
    }

    func testEncodeUnixEpochToJSON() {
        do {
            struct A: Codable {
                @CustomCoding<UnixEpochDateCoder> var date: Date
            }
            let a = A(date: Date(timeIntervalSince1970: 23_983_978_378))
            let data = try JSONEncoder().encode(a)
            let jsonString = String(data: data, encoding: .utf8)
            XCTAssertEqual(jsonString, "{\"date\":23983978378}")
        } catch {
            XCTFail("\(error)")
        }
    }
}
