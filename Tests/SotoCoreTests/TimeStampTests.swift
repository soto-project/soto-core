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

import NIOHTTP1
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
            struct A: AWSDecodableShape {
                let date: Date
            }
            let byteBuffer = ByteBufferAllocator().buffer(string: "{\"date\": 234876345}")
            let response = AWSHTTPResponseImpl(status: .ok, headers: [:], body: byteBuffer)
            let awsResponse = try AWSResponse(from: response, serviceProtocol: .json(version: "1.1"))
            let a: A = try awsResponse.generateOutputShape(operation: "TestOperation")
            XCTAssertEqual(a.date.timeIntervalSince1970, 234_876_345)
        } catch {
            XCTFail("\(error)")
        }
    }

    func testEncodeJSON() {
        struct A: AWSEncodableShape {
            var date: Date
        }
        let a = A(date: Date(timeIntervalSince1970: 23_984_978_378))
        var request: AWSRequest?
        XCTAssertNoThrow(request = try AWSRequest(operation: "test", path: "/", httpMethod: .GET, input: a, configuration: createServiceConfig()))
        #if os(Linux)
        XCTAssertEqual(request?.body.asString(), "{\"date\":23984978378.0}")
        #else
        XCTAssertEqual(request?.body.asString(), "{\"date\":23984978378}")
        #endif
    }

    func testDecodeXML() {
        do {
            struct A: AWSDecodableShape {
                let date: Date
                let date2: Date
            }
            let byteBuffer = ByteBufferAllocator().buffer(string: "<A><date>2017-01-01T00:01:00.000Z</date><date2>2017-01-01T00:02:00Z</date2></A>")
            let response = AWSHTTPResponseImpl(status: .ok, headers: [:], body: byteBuffer)
            let awsResponse = try AWSResponse(from: response, serviceProtocol: .restxml)
            let a: A = try awsResponse.generateOutputShape(operation: "TestOperation")
            XCTAssertEqual(self.dateFormatter.string(from: a.date), "2017-01-01T00:01:00.000Z")
            XCTAssertEqual(self.dateFormatter.string(from: a.date2), "2017-01-01T00:02:00.000Z")
        } catch {
            XCTFail("\(error)")
        }
    }

    func testEncodeXML() {
        struct A: AWSEncodableShape {
            var date: Date
        }
        let a = A(date: dateFormatter.date(from: "2017-11-01T00:15:00.000Z")!)
        var request: AWSRequest?
        XCTAssertNoThrow(request = try AWSRequest(operation: "test", path: "/", httpMethod: .GET, input: a, configuration: createServiceConfig(serviceProtocol: .restxml)))
        XCTAssertEqual(request?.body.asString(), "<?xml version=\"1.0\" encoding=\"UTF-8\"?><A><date>2017-11-01T00:15:00.000Z</date></A>")
    }

    func testEncodeQuery() {
        struct A: AWSEncodableShape {
            var date: Date
        }
        let a = A(date: dateFormatter.date(from: "2017-11-01T00:15:00.000Z")!)
        var request: AWSRequest?
        XCTAssertNoThrow(request = try AWSRequest(operation: "test", path: "/", httpMethod: .GET, input: a, configuration: createServiceConfig(serviceProtocol: .query)))
        XCTAssertEqual(request?.body.asString(), "Action=test&Version=01-01-2001&date=2017-11-01T00%3A15%3A00.000Z")
    }

    func testDecodeHeader() {
        do {
            struct A: AWSDecodableShape {
                static let _encoding = [AWSMemberEncoding(label: "date", location: .header(locationName: "Date"))]
                let date: Date
                private enum CodingKeys: String, CodingKey {
                    case date = "Date"
                }
            }
            let response = AWSHTTPResponseImpl(status: .ok, headers: ["Date": "Tue, 15 Nov 1994 12:45:27 GMT"], body: nil)
            let awsResponse = try AWSResponse(from: response, serviceProtocol: .restxml)
            let a: A = try awsResponse.generateOutputShape(operation: "TestOperation")
            XCTAssertEqual(self.dateFormatter.string(from: a.date), "1994-11-15T12:45:27.000Z")
        } catch {
            XCTFail("\(error)")
        }
    }

    func testDecodeISOFromXML() {
        do {
            struct A: AWSDecodableShape {
                @CustomCoding<ISO8601DateCoder> var date: Date
            }
            let byteBuffer = ByteBufferAllocator().buffer(string: "<A><date>2017-01-01T00:01:00.000Z</date></A>")
            let response = AWSHTTPResponseImpl(status: .ok, headers: [:], body: byteBuffer)
            let awsResponse = try AWSResponse(from: response, serviceProtocol: .restxml)
            let a: A = try awsResponse.generateOutputShape(operation: "TestOperation")
            XCTAssertEqual(self.dateFormatter.string(from: a.date), "2017-01-01T00:01:00.000Z")
        } catch {
            XCTFail("\(error)")
        }
    }

    func testDecodeISONoMillisecondFromXML() {
        do {
            struct A: AWSDecodableShape {
                @CustomCoding<ISO8601DateCoder> var date: Date
            }
            let byteBuffer = ByteBufferAllocator().buffer(string: "<A><date>2017-01-01T00:01:00Z</date></A>")
            let response = AWSHTTPResponseImpl(status: .ok, headers: [:], body: byteBuffer)
            let awsResponse = try AWSResponse(from: response, serviceProtocol: .restxml)
            let a: A = try awsResponse.generateOutputShape(operation: "TestOperation")
            XCTAssertEqual(self.dateFormatter.string(from: a.date), "2017-01-01T00:01:00.000Z")
        } catch {
            XCTFail("\(error)")
        }
    }

    func testDecodeHttpFormattedTimestamp() {
        do {
            struct A: AWSDecodableShape {
                @CustomCoding<HTTPHeaderDateCoder> var date: Date
            }
            let xml = "<A><date>Tue, 15 Nov 1994 12:45:26 GMT</date></A>"
            let byteBuffer = ByteBufferAllocator().buffer(string: xml)
            let response = AWSHTTPResponseImpl(status: .ok, headers: [:], body: byteBuffer)
            let awsResponse = try AWSResponse(from: response, serviceProtocol: .restxml)
            let a: A = try awsResponse.generateOutputShape(operation: "TestOperation")
            XCTAssertEqual(self.dateFormatter.string(from: a.date), "1994-11-15T12:45:26.000Z")
        } catch {
            XCTFail("\(error)")
        }
    }

    func testDecodeUnixEpochTimestamp() {
        do {
            struct A: AWSDecodableShape {
                @CustomCoding<UnixEpochDateCoder> var date: Date
            }
            let xml = "<A><date>1221382800</date></A>"
            let byteBuffer = ByteBufferAllocator().buffer(string: xml)
            let response = AWSHTTPResponseImpl(status: .ok, headers: [:], body: byteBuffer)
            let awsResponse = try AWSResponse(from: response, serviceProtocol: .restxml)
            let a: A = try awsResponse.generateOutputShape(operation: "TestOperation")
            XCTAssertEqual(self.dateFormatter.string(from: a.date), "2008-09-14T09:00:00.000Z")
        } catch {
            XCTFail("\(error)")
        }
    }

    func testEncodeISO8601ToXML() {
        struct A: AWSEncodableShape {
            @CustomCoding<ISO8601DateCoder> var date: Date
        }
        let a = A(date: dateFormatter.date(from: "2019-05-01T00:00:00.001Z")!)
        var request: AWSRequest?
        XCTAssertNoThrow(request = try AWSRequest(operation: "test", path: "/", httpMethod: .GET, input: a, configuration: createServiceConfig(serviceProtocol: .restxml)))
        XCTAssertEqual(request?.body.asString(), "<?xml version=\"1.0\" encoding=\"UTF-8\"?><A><date>2019-05-01T00:00:00.001Z</date></A>")
    }

    func testEncodeHTTPHeaderToJSON() {
        struct A: AWSEncodableShape {
            @CustomCoding<HTTPHeaderDateCoder> var date: Date
        }
        let a = A(date: dateFormatter.date(from: "2019-05-01T00:00:00.001Z")!)
        var request: AWSRequest?
        XCTAssertNoThrow(request = try AWSRequest(operation: "test", path: "/", httpMethod: .GET, input: a, configuration: createServiceConfig()))
        XCTAssertEqual(request?.body.asString(), "{\"date\":\"Wed, 1 May 2019 00:00:00 GMT\"}")
    }

    func testEncodeUnixEpochToJSON() {
        struct A: AWSEncodableShape {
            @CustomCoding<UnixEpochDateCoder> var date: Date
        }
        let a = A(date: Date(timeIntervalSince1970: 23_983_978_378))
        var request: AWSRequest?
        XCTAssertNoThrow(request = try AWSRequest(operation: "test", path: "/", httpMethod: .GET, input: a, configuration: createServiceConfig()))
        XCTAssertEqual(request?.body.asString(), "{\"date\":23983978378}")
    }

    // MARK: Types used in tests

    struct AWSHTTPResponseImpl: AWSHTTPResponse {
        let status: HTTPResponseStatus
        let headers: HTTPHeaders
        let body: ByteBuffer?

        init(status: HTTPResponseStatus, headers: HTTPHeaders, body: ByteBuffer?) {
            self.status = status
            self.headers = headers
            self.body = body
        }

        init(status: HTTPResponseStatus, headers: HTTPHeaders, bodyData: Data?) {
            var body: ByteBuffer?
            if let bodyData = bodyData {
                body = ByteBufferAllocator().buffer(capacity: bodyData.count)
                body?.writeBytes(bodyData)
            }
            self.init(status: status, headers: headers, body: body)
        }
    }
}
