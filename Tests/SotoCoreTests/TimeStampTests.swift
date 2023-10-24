//===----------------------------------------------------------------------===//
//
// This source file is part of the Soto for AWS open source project
//
// Copyright (c) 2017-2023 the Soto project authors
// Licensed under Apache License v2.0
//
// See LICENSE.txt for license information
// See CONTRIBUTORS.txt for the list of Soto project authors
//
// SPDX-License-Identifier: Apache-2.0
//
//===----------------------------------------------------------------------===//

#if compiler(>=5.7) && os(Linux)
@preconcurrency import struct Foundation.Date
#else
import struct Foundation.Date
#endif
import NIOHTTP1
@testable @_spi(SotoInternal) import SotoCore
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

    func testDecodeJSON() async throws {
        do {
            struct A: AWSDecodableShape {
                let date: Date
            }
            let byteBuffer = ByteBuffer(string: "{\"date\": 234876345}")
            let response = AWSHTTPResponse(status: .ok, headers: [:], body: .init(buffer: byteBuffer))
            let a: A = try response.generateOutputShape(operation: "TestOperation", serviceProtocol: .json(version: "1.1"))
            XCTAssertEqual(a.date.timeIntervalSince1970, 234_876_345)
        } catch {
            XCTFail("\(error)")
        }
    }

    func testEncodeJSON() async throws {
        struct A: AWSEncodableShape {
            var date: Date
        }
        let a = A(date: Date(timeIntervalSince1970: 23_984_978_378))
        var request: AWSHTTPRequest?
        XCTAssertNoThrow(request = try AWSHTTPRequest(operation: "test", path: "/", method: .GET, input: a, configuration: createServiceConfig()))
        #if os(Linux)
        XCTAssertEqual(request?.body.asString(), "{\"date\":23984978378.0}")
        #else
        XCTAssertEqual(request?.body.asString(), "{\"date\":23984978378}")
        #endif
    }

    func testDecodeXML() async throws {
        do {
            struct A: AWSDecodableShape {
                let date: Date
                let date2: Date
            }
            let byteBuffer = ByteBuffer(string: "<A><date>2017-01-01T00:01:00.000Z</date><date2>2017-01-01T00:02:00Z</date2></A>")
            let response = AWSHTTPResponse(status: .ok, headers: [:], body: .init(buffer: byteBuffer))
            let a: A = try response.generateOutputShape(operation: "TestOperation", serviceProtocol: .restxml)
            XCTAssertEqual(self.dateFormatter.string(from: a.date), "2017-01-01T00:01:00.000Z")
            XCTAssertEqual(self.dateFormatter.string(from: a.date2), "2017-01-01T00:02:00.000Z")
        } catch {
            XCTFail("\(error)")
        }
    }

    func testEncodeXML() async throws {
        struct A: AWSEncodableShape {
            var date: Date
        }
        let a = A(date: dateFormatter.date(from: "2017-11-01T00:15:00.000Z")!)
        var request: AWSHTTPRequest?
        XCTAssertNoThrow(request = try AWSHTTPRequest(operation: "test", path: "/", method: .GET, input: a, configuration: createServiceConfig(serviceProtocol: .restxml)))
        XCTAssertEqual(request?.body.asString(), "<?xml version=\"1.0\" encoding=\"UTF-8\"?><A><date>2017-11-01T00:15:00.000Z</date></A>")
    }

    func testEncodeQuery() async throws {
        struct A: AWSEncodableShape {
            var date: Date
        }
        let a = A(date: dateFormatter.date(from: "2017-11-01T00:15:00.000Z")!)
        var request: AWSHTTPRequest?
        XCTAssertNoThrow(request = try AWSHTTPRequest(operation: "test", path: "/", method: .GET, input: a, configuration: createServiceConfig(serviceProtocol: .query)))
        XCTAssertEqual(request?.body.asString(), "Action=test&Version=01-01-2001&date=2017-11-01T00%3A15%3A00.000Z")
    }

    func testDecodeHeader() async throws {
        do {
            struct A: AWSDecodableShape {
                let date: Date
                public init(from decoder: Decoder) throws {
                    let response = decoder.userInfo[.awsResponse]! as! ResponseDecodingContainer
                    self.date = try response.decodeHeader(Date.self, key: "Date")
                }
            }
            let response = AWSHTTPResponse(status: .ok, headers: ["Date": "Tue, 15 Nov 1994 12:45:27 GMT"])
            let a: A = try response.generateOutputShape(operation: "TestOperation", serviceProtocol: .restxml)
            XCTAssertEqual(self.dateFormatter.string(from: a.date), "1994-11-15T12:45:27.000Z")
        } catch {
            XCTFail("\(error)")
        }
    }

    func testDecodeISOFromXML() async throws {
        do {
            struct A: AWSDecodableShape {
                @CustomCoding<ISO8601DateCoder> var date: Date
            }
            let byteBuffer = ByteBuffer(string: "<A><date>2017-01-01T00:01:00.000Z</date></A>")
            let response = AWSHTTPResponse(status: .ok, headers: [:], body: .init(buffer: byteBuffer))
            let a: A = try response.generateOutputShape(operation: "TestOperation", serviceProtocol: .restxml)
            XCTAssertEqual(self.dateFormatter.string(from: a.date), "2017-01-01T00:01:00.000Z")
        } catch {
            XCTFail("\(error)")
        }
    }

    func testDecodeISONoMillisecondFromXML() async throws {
        do {
            struct A: AWSDecodableShape {
                @CustomCoding<ISO8601DateCoder> var date: Date
            }
            let byteBuffer = ByteBuffer(string: "<A><date>2017-01-01T00:01:00Z</date></A>")
            let response = AWSHTTPResponse(status: .ok, headers: [:], body: .init(buffer: byteBuffer))
            let a: A = try response.generateOutputShape(operation: "TestOperation", serviceProtocol: .restxml)
            XCTAssertEqual(self.dateFormatter.string(from: a.date), "2017-01-01T00:01:00.000Z")
        } catch {
            XCTFail("\(error)")
        }
    }

    func testDecodeHttpFormattedTimestamp() async throws {
        do {
            struct A: AWSDecodableShape {
                @CustomCoding<HTTPHeaderDateCoder> var date: Date
            }
            let xml = "<A><date>Tue, 15 Nov 1994 12:45:26 GMT</date></A>"
            let byteBuffer = ByteBuffer(string: xml)
            let response = AWSHTTPResponse(status: .ok, headers: [:], body: .init(buffer: byteBuffer))
            let a: A = try response.generateOutputShape(operation: "TestOperation", serviceProtocol: .restxml)
            XCTAssertEqual(self.dateFormatter.string(from: a.date), "1994-11-15T12:45:26.000Z")
        } catch {
            XCTFail("\(error)")
        }
    }

    func testDecodeUnixEpochTimestamp() async throws {
        do {
            struct A: AWSDecodableShape {
                @CustomCoding<UnixEpochDateCoder> var date: Date
            }
            let xml = "<A><date>1221382800</date></A>"
            let byteBuffer = ByteBuffer(string: xml)
            let response = AWSHTTPResponse(status: .ok, headers: [:], body: .init(buffer: byteBuffer))
            let a: A = try response.generateOutputShape(operation: "TestOperation", serviceProtocol: .restxml)
            XCTAssertEqual(self.dateFormatter.string(from: a.date), "2008-09-14T09:00:00.000Z")
        } catch {
            XCTFail("\(error)")
        }
    }

    func testEncodeISO8601ToXML() async throws {
        struct A: AWSEncodableShape {
            @CustomCoding<ISO8601DateCoder> var date: Date
        }
        let a = A(date: dateFormatter.date(from: "2019-05-01T00:00:00.001Z")!)
        var request: AWSHTTPRequest?
        XCTAssertNoThrow(request = try AWSHTTPRequest(operation: "test", path: "/", method: .GET, input: a, configuration: createServiceConfig(serviceProtocol: .restxml)))
        XCTAssertEqual(request?.body.asString(), "<?xml version=\"1.0\" encoding=\"UTF-8\"?><A><date>2019-05-01T00:00:00.001Z</date></A>")
    }

    func testEncodeHTTPHeaderToJSON() async throws {
        struct A: AWSEncodableShape {
            @CustomCoding<HTTPHeaderDateCoder> var date: Date
        }
        let a = A(date: dateFormatter.date(from: "2019-05-01T00:00:00.001Z")!)
        var request: AWSHTTPRequest?
        XCTAssertNoThrow(request = try AWSHTTPRequest(operation: "test", path: "/", method: .GET, input: a, configuration: createServiceConfig()))
        XCTAssertEqual(request?.body.asString(), "{\"date\":\"Wed, 1 May 2019 00:00:00 GMT\"}")
    }

    func testEncodeUnixEpochToJSON() async throws {
        struct A: AWSEncodableShape {
            @CustomCoding<UnixEpochDateCoder> var date: Date
        }
        let a = A(date: Date(timeIntervalSince1970: 23_983_978_378))
        var request: AWSHTTPRequest?
        XCTAssertNoThrow(request = try AWSHTTPRequest(operation: "test", path: "/", method: .GET, input: a, configuration: createServiceConfig()))
        XCTAssertEqual(request?.body.asString(), "{\"date\":23983978378}")
    }
}
