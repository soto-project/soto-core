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
import NIO
import NIOHTTP1
import AWSTestUtils
import AWSXML
@testable import AWSSDKSwiftCore

class AWSResponseTests: XCTestCase {

    func testHeaderResponseDecoding() {
        struct Output: AWSDecodableShape {
            static let _encoding = [AWSMemberEncoding(label: "h", location: .header(locationName: "header-member"))]
            let h: String
            private enum CodingKeys: String, CodingKey {
                case h = "header-member"
            }
        }
        let response = AWSHTTPResponseImpl(
            status: .ok,
            headers: ["header-member": "test-header"],
            bodyData: nil
        )

        // XML
        var awsXMLResponse: AWSResponse? = nil
        var xmlResult: Output? = nil
        XCTAssertNoThrow(awsXMLResponse = try AWSResponse(from: response, serviceProtocol: .query, raw: false))
        XCTAssertNoThrow(xmlResult = try awsXMLResponse?.generateOutputShape(operation: "Test"))
        XCTAssertEqual(xmlResult?.h, "test-header")

        // JSON
        var awsJSONResponse: AWSResponse? = nil
        var jsonResult: Output? = nil
        XCTAssertNoThrow(awsJSONResponse = try AWSResponse(from: response, serviceProtocol: .restjson, raw: false))
        XCTAssertNoThrow(jsonResult = try awsJSONResponse?.generateOutputShape(operation: "Test"))
        XCTAssertEqual(jsonResult?.h, "test-header")
    }

    func testStatusCodeResponseDecoding() {
        struct Output: AWSDecodableShape {
            static let _encoding = [AWSMemberEncoding(label: "status", location: .statusCode)]
            let status: Int
        }
        let response = AWSHTTPResponseImpl(
            status: .ok,
            headers: HTTPHeaders(),
            bodyData: nil
        )

        // XML
        var awsXMLResponse: AWSResponse? = nil
        var xmlResult: Output? = nil
        XCTAssertNoThrow(awsXMLResponse = try AWSResponse(from: response, serviceProtocol: .query, raw: false))
        XCTAssertNoThrow(xmlResult = try awsXMLResponse?.generateOutputShape(operation: "Test"))
        XCTAssertEqual(xmlResult?.status, 200)

        // JSON
        var awsJSONResponse: AWSResponse? = nil
        var jsonResult: Output? = nil
        XCTAssertNoThrow(awsJSONResponse = try AWSResponse(from: response, serviceProtocol: .restjson, raw: false))
        XCTAssertNoThrow(jsonResult = try awsJSONResponse?.generateOutputShape(operation: "Test"))
        XCTAssertEqual(jsonResult?.status, 200)
    }

    //MARK: XML tests
    
    func testValidateXMLResponse() {
        class Output : AWSDecodableShape {
            let name : String
        }
        let responseBody = "<Output><name>hello</name></Output>"
        let response = AWSHTTPResponseImpl(
            status: .ok,
            headers: HTTPHeaders(),
            bodyData: Data(responseBody.utf8)
        )
        
        var awsResponse: AWSResponse? = nil
        var output: Output? = nil
        XCTAssertNoThrow(awsResponse = try AWSResponse(from: response, serviceProtocol: .restxml, raw: false))
        XCTAssertNoThrow(output = try awsResponse?.generateOutputShape(operation: "Test"))
        XCTAssertEqual(output?.name, "hello")
    }

    func testValidateXMLCodablePayloadResponse() {
        class Output : AWSDecodableShape & AWSShapeWithPayload {
            static let _encoding = [AWSMemberEncoding(label: "contentType", location: .header(locationName: "content-type"))]
            static let _payloadPath: String = "name"
            let name : String
            let contentType: String

            private enum CodingKeys: String, CodingKey {
                case name = "name"
                case contentType = "content-type"
            }
        }
        let response = AWSHTTPResponseImpl(
            status: .ok,
            headers: ["Content-Type":"application/xml"],
            bodyData: "<name>hello</name>".data(using: .utf8)!
        )

        var awsResponse: AWSResponse? = nil
        var output: Output? = nil
        XCTAssertNoThrow(awsResponse = try AWSResponse(from: response, serviceProtocol: .restxml, raw: false))
        XCTAssertNoThrow(output = try awsResponse?.generateOutputShape(operation: "Test"))
        XCTAssertEqual(output?.name, "hello")
        XCTAssertEqual(output?.contentType, "application/xml")
    }

    func testValidateXMLRawPayloadResponse() {
        class Output : AWSDecodableShape, AWSShapeWithPayload {
            static let _payloadPath: String = "body"
            static let _payloadOptions: PayloadOptions = .raw
            let body : AWSPayload
        }
        let response = AWSHTTPResponseImpl(
            status: .ok,
            headers: HTTPHeaders(),
            bodyData: Data("{\"name\":\"hello\"}".utf8)
        )
        
        var awsResponse: AWSResponse? = nil
        var output: Output? = nil
        XCTAssertNoThrow(awsResponse = try AWSResponse(from: response, serviceProtocol: .restxml, raw: true))
        XCTAssertNoThrow(output = try awsResponse?.generateOutputShape(operation: "Test"))
        XCTAssertEqual(output?.body.asData(), Data("{\"name\":\"hello\"}".utf8))
    }

    //MARK: JSON tests
    
    func testValidateJSONResponse() {
        class Output : AWSDecodableShape {
            let name : String
        }
        let response = AWSHTTPResponseImpl(
            status: .ok,
            headers: HTTPHeaders(),
            bodyData: Data("{\"name\":\"hello\"}".utf8)
        )
        
        var awsResponse: AWSResponse? = nil
        var output: Output? = nil
        XCTAssertNoThrow(awsResponse = try AWSResponse(from: response, serviceProtocol: .json(version: "1.1"), raw: false))
        XCTAssertNoThrow(output = try awsResponse?.generateOutputShape(operation: "Test"))
        XCTAssertEqual(output?.name, "hello")
    }

    func testValidateJSONCodablePayloadResponse() {
        class Output2 : AWSDecodableShape {
            let name : String
        }
        struct Output : AWSDecodableShape & AWSShapeWithPayload {
            static let _payloadPath: String = "output2"
            let output2 : Output2
        }
        let response = AWSHTTPResponseImpl(
            status: .ok,
            headers: HTTPHeaders(),
            bodyData: Data("{\"name\":\"hello\"}".utf8)
        )
        
        var awsResponse: AWSResponse? = nil
        var output: Output? = nil
        XCTAssertNoThrow(awsResponse = try AWSResponse(from: response, serviceProtocol: .json(version: "1.1"), raw: false))
        XCTAssertNoThrow(output = try awsResponse?.generateOutputShape(operation: "Test"))
        XCTAssertEqual(output?.output2.name, "hello")
    }

    func testValidateJSONRawPayloadResponse() {
        struct Output : AWSDecodableShape, AWSShapeWithPayload {
            static let _payloadPath: String = "body"
            static let _payloadOptions: PayloadOptions = .raw
            public static var _encoding = [
                AWSMemberEncoding(label: "contentType", location: .header(locationName: "content-type")),
            ]
            let body : AWSPayload
        }
        let response = AWSHTTPResponseImpl(
            status: .ok,
            headers: ["Content-Type":"application/json"],
            bodyData: Data("{\"name\":\"hello\"}".utf8)
        )
        
        var awsResponse: AWSResponse? = nil
        var output: Output? = nil
        XCTAssertNoThrow(awsResponse = try AWSResponse(from: response, serviceProtocol: .json(version: "1.1"), raw: true))
        XCTAssertNoThrow(output = try awsResponse?.generateOutputShape(operation: "Test"))
        XCTAssertEqual(output?.body.asString(), "{\"name\":\"hello\"}")
    }

    //MARK: Error tests
    
    func testJSONError() {
        let response = AWSHTTPResponseImpl(
            status: .notFound,
            headers: HTTPHeaders(),
            bodyData: "{\"__type\":\"ResourceNotFoundException\", \"message\": \"Donald Where's Your Troosers?\"}".data(using: .utf8)!
        )
        let service = createServiceConfig(serviceProtocol: .json(version: "1.1"), possibleErrorTypes: [ServiceErrorType.self])
        
        var awsResponse: AWSResponse? = nil
        XCTAssertNoThrow(awsResponse = try AWSResponse(from: response, serviceProtocol: .json(version: "1.1"), raw: false))
        let error = awsResponse?.generateError(serviceConfig: service)
        XCTAssertEqual(error as? ServiceErrorType, .resourceNotFoundException(message: "Donald Where's Your Troosers?"))
    }

    func testXMLError() {
        let response = AWSHTTPResponseImpl(
            status: .notFound,
            headers: HTTPHeaders(),
            bodyData: "<Error><Code>NoSuchKey</Code><Message>It doesn't exist</Message></Error>".data(using: .utf8)!
        )
        let service = createServiceConfig(serviceProtocol: .restxml, possibleErrorTypes: [ServiceErrorType.self])
        
        var awsResponse: AWSResponse? = nil
        XCTAssertNoThrow(awsResponse = try AWSResponse(from: response, serviceProtocol: .restxml, raw: false))
        let error = awsResponse?.generateError(serviceConfig: service)
        XCTAssertEqual(error as? ServiceErrorType, .noSuchKey(message: "It doesn't exist"))
    }

    func testQueryError() {
        let response = AWSHTTPResponseImpl(
            status: .notFound,
            headers: HTTPHeaders(),
            bodyData: "<ErrorResponse><Error><Code>MessageRejected</Code><Message>Don't like it</Message></Error></ErrorResponse>".data(using: .utf8)!
        )
        let queryService = createServiceConfig(serviceProtocol: .query, possibleErrorTypes: [ServiceErrorType.self])
        
        var awsResponse: AWSResponse? = nil
        XCTAssertNoThrow(awsResponse = try AWSResponse(from: response, serviceProtocol: .query, raw: false))
        let error = awsResponse?.generateError(serviceConfig: queryService)
        XCTAssertEqual(error as? ServiceErrorType, .messageRejected(message: "Don't like it"))
    }

    func testEC2Error() {
        let response = AWSHTTPResponseImpl(
            status: .notFound,
            headers: HTTPHeaders(),
            bodyData: "<Errors><Error><Code>NoSuchKey</Code><Message>It doesn't exist</Message></Error></Errors>".data(using: .utf8)!
        )
        let service = createServiceConfig(serviceProtocol: .ec2)
        
        var awsResponse: AWSResponse? = nil
        XCTAssertNoThrow(awsResponse = try AWSResponse(from: response, serviceProtocol: .ec2, raw: false))
        let error = awsResponse?.generateError(serviceConfig: service) as? AWSResponseError
        XCTAssertEqual(error?.errorCode, "NoSuchKey")
        XCTAssertEqual(error?.message, "It doesn't exist")
    }

    //MARK: Miscellaneous tests
    
    func testProcessHAL() {
        struct Output : AWSDecodableShape {
            let s: String
            let i: Int
        }
        struct Output2 : AWSDecodableShape {
            let a: [Output]
            let d: Double
            let b: Bool
        }
        let response = AWSHTTPResponseImpl(
            status: .ok,
            headers: ["Content-Type":"application/hal+json"],
            bodyData: Data(#"{"_embedded": {"a": [{"s":"Hello", "i":1234}, {"s":"Hello2", "i":12345}]}, "d":3.14, "b":true}"#.utf8)
        )
        
        var awsResponse: AWSResponse? = nil
        var output: Output2? = nil
        XCTAssertNoThrow(awsResponse = try AWSResponse(from: response, serviceProtocol: .json(version: "1.1"), raw: false))
        XCTAssertNoThrow(output = try awsResponse?.generateOutputShape(operation: "Test"))
        XCTAssertEqual(output?.a.count, 2)
        XCTAssertEqual(output?.d, 3.14)
        XCTAssertEqual(output?.a[1].s, "Hello2")
    }

    //MARK: Types used in tests
    
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
            var body: ByteBuffer? = nil
            if let bodyData = bodyData {
                body = ByteBufferAllocator().buffer(capacity: bodyData.count)
                body?.writeBytes(bodyData)
            }
            self.init(status: status, headers: headers, body: body)
        }
    }

    enum ServiceErrorType: AWSErrorType, Equatable {
        case resourceNotFoundException(message: String?)
        case noSuchKey(message: String?)
        case messageRejected(message: String?)

        init?(errorCode: String, message: String?){
            switch errorCode {
            case "ResourceNotFoundException":
                self = .resourceNotFoundException(message: message)
            case "NoSuchKey":
                self = .noSuchKey(message: message)
            case "MessageRejected":
                self = .messageRejected(message: message)
            default:
                return nil
            }
        }

        var description : String {
            switch self {
            case .resourceNotFoundException(let message):
                return "ResourceNotFoundException :\(message ?? "")"
            case .noSuchKey(let message):
                return "NoSuchKey :\(message ?? "")"
            case .messageRejected(let message):
                return "MessageRejected :\(message ?? "")"
            }
        }
    }
}

