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
import AsyncHTTPClient
import NIO
import NIOHTTP1
import AWSTestUtils
import AWSXML
@testable import AWSSDKSwiftCore

class AWSClientTests: XCTestCase {

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

    struct C: AWSEncodableShape {
        public static var _encoding: [AWSMemberEncoding] = [
             AWSMemberEncoding(label: "value", location: .header(locationName: "value"))
        ]
        let value = "<html><body><a href=\"https://redsox.com\">Test</a></body></html>"

        private enum CodingKeys: String, CodingKey {
            case value = "Value"
        }
    }

    struct E: AWSEncodableShape & Decodable {
        let Member = ["memberKey": "memberValue", "memberKey2" : "memberValue2"]

        private enum CodingKeys: String, CodingKey {
            case Member = "Member"
        }
    }

    struct F: AWSEncodableShape & AWSShapeWithPayload {
        public static let payloadPath: String = "fooParams"

        public let fooParams: E?

        public init(fooParams: E? = nil) {
            self.fooParams = fooParams
        }

        private enum CodingKeys: String, CodingKey {
            case fooParams = "fooParams"
        }
    }


    func testGetCredential() {
        let client = createAWSClient(accessKeyId: "key", secretAccessKey: "secret")

        do {
            let credentialForSignature = try client.credentialProvider.getCredential(on: client.eventLoopGroup.next()).wait()
            XCTAssertEqual(credentialForSignature.accessKeyId, "key")
            XCTAssertEqual(credentialForSignature.secretAccessKey, "secret")
        } catch {
            XCTFail(error.localizedDescription)
        }
    }

    // this test only really works on Linux as it requires the MetaDataService. On mac it will just pass automatically
    func testExpiredCredential() {
        let client = createAWSClient()

        do {
            let credentials = try client.credentialProvider.getCredential(on: client.eventLoopGroup.next()).wait()
            print(credentials)
        } catch NIO.ChannelError.connectTimeout(_) {
            // credentials request should fail. One possible error is a connectTimerout
        } catch is NIOConnectionError {
                // credentials request should fail. One possible error is a connection error
//        } catch MetaDataServiceError.couldNotGetInstanceRoleName {
            // credentials request fails in a slightly different way if it finds the IP
        } catch {
            XCTFail("Unexpected error \(error)")
        }
    }

    func testPartitionEndpoints() throws {
        let client = createAWSClient(
            serviceEndpoints: ["aws-global":"service.aws.amazon.com"],
            partitionEndpoints: [.aws: (endpoint: "aws-global", region: .euwest1)]
        )
        XCTAssertEqual(client.region, .euwest1)

        let awsRequest = try client.createAWSRequest(operation: "test", path: "/", httpMethod: "GET")
        XCTAssertEqual(awsRequest.url.absoluteString, "https://service.aws.amazon.com/")
    }

    func testCreateAwsRequestWithKeywordInHeader() {
        struct KeywordRequest: AWSEncodableShape {
            static var _encoding: [AWSMemberEncoding] = [
                AWSMemberEncoding(label: "repeat", location: .header(locationName: "repeat")),
            ]
            let `repeat`: String
        }
        let client = createAWSClient()
        do {
            let request = KeywordRequest(repeat: "Repeat")
            let awsRequest = try client.createAWSRequest(operation: "Keyword", path: "/", httpMethod: "POST", input: request)
            XCTAssertEqual(awsRequest.httpHeaders["repeat"] as? String, "Repeat")
            XCTAssertTrue(awsRequest.body.asPayload().isEmpty)
        } catch {
            XCTFail(error.localizedDescription)
        }
    }

    func testCreateAwsRequestWithKeywordInQuery() {
        struct KeywordRequest: AWSEncodableShape {
            static var _encoding: [AWSMemberEncoding] = [
                AWSMemberEncoding(label: "self", location: .querystring(locationName: "self")),
            ]
            let `self`: String
        }
        let client = createAWSClient(region: .cacentral1, service: "s3")
        do {
            let request = KeywordRequest(self: "KeywordRequest")
            let awsRequest = try client.createAWSRequest(operation: "Keyword", path: "/", httpMethod: "POST", input: request)
            XCTAssertEqual(awsRequest.url, URL(string:"https://s3.ca-central-1.amazonaws.com/?self=KeywordRequest")!)
            XCTAssertEqual(awsRequest.body.asByteBuffer(), nil)
        } catch {
            XCTFail(error.localizedDescription)
        }
    }

    func testCreateNIORequest() {
        let input2 = E()

        let kinesisClient = AWSClient(
            accessKeyId: "foo",
            secretAccessKey: "bar",
            region: nil,
            amzTarget: "Kinesis_20131202",
            service: "kinesis",
            serviceProtocol: .json(version: "1.1"),
            apiVersion: "2013-12-02",
            middlewares: [],
            possibleErrorTypes: [ServiceErrorType.self],
            httpClientProvider: .createNew
        )

        let client = createAWSClient(service: "kinesis", serviceProtocol: .json(version: "1.1"))
        do {
            let awsRequest = try client.createAWSRequest(
                operation: "PutRecord",
                path: "/",
                httpMethod: "POST",
                input: input2
            )

            let awsHTTPRequest: AWSHTTPRequest = awsRequest.createHTTPRequest(signer: try kinesisClient.signer.wait())
            XCTAssertEqual(awsHTTPRequest.method, HTTPMethod.POST)
            if let host = awsHTTPRequest.headers.first(where: { $0.name == "Host" }) {
                XCTAssertEqual(host.value, "kinesis.us-east-1.amazonaws.com")
            }
            if let contentType = awsHTTPRequest.headers.first(where: { $0.name == "Content-Type" }) {
                XCTAssertEqual(contentType.value, "application/x-amz-json-1.1")
            }
            if let xAmzTarget = awsHTTPRequest.headers.first(where: { $0.name == "x-amz-target" }) {
                XCTAssertEqual(xAmzTarget.value, "Kinesis_20131202.PutRecord")
            }
        } catch {
            XCTFail(error.localizedDescription)
        }
    }

    func testUnsignedClient() {
        let input = E()
        let client = createAWSClient(accessKeyId: "", secretAccessKey: "")
        
        var awsRequest: AWSRequest?
        XCTAssertNoThrow(awsRequest = try client.createAWSRequest(
            operation: "CopyObject",
            path: "/",
            httpMethod: "PUT",
            input: input
        ))

        var request: AWSHTTPRequest?
        XCTAssertNoThrow(request = awsRequest?.createHTTPRequest(signer: try client.signer.wait()))
        XCTAssertNil(request?.headers["Authorization"].first)
    }
    
    func testSignedClient() {
        let input = E()
        let client = createAWSClient(accessKeyId: "foo", secretAccessKey: "bar")
        
        for httpMethod in ["GET","HEAD","PUT","DELETE","POST","PATCH"] {
            var awsRequest: AWSRequest?
            
            XCTAssertNoThrow(awsRequest = try client.createAWSRequest(
                operation: "Test",
                path: "/",
                httpMethod: httpMethod,
                input: input
            ))
            
            var request: AWSHTTPRequest?
            XCTAssertNoThrow(request = awsRequest?.createHTTPRequest(signer: try client.signer.wait()))
            XCTAssertNotNil(request?.headers["Authorization"].first)
        }
    }

    func testProtocolContentType() throws {
        struct Object: AWSEncodableShape {
            let string: String
        }
        struct Object2: AWSEncodableShape & AWSShapeWithPayload {
            static var payloadPath = "payload"
            let payload: AWSPayload
            private enum CodingKeys: CodingKey {}
        }
        let object = Object(string: "Name")
        let object2 = Object2(payload: .string("Payload"))

        let client = createAWSClient(serviceProtocol: .json(version: "1.1"))
        let request = try client.createAWSRequest(operation: "test", path: "/", httpMethod: "POST", input: object)
        XCTAssertEqual(request.getHttpHeaders()["content-type"].first, "application/x-amz-json-1.1")

        let client2 = createAWSClient(serviceProtocol: .restjson)
        let request2 = try client2.createAWSRequest(operation: "test", path: "/", httpMethod: "POST", input: object)
        XCTAssertEqual(request2.getHttpHeaders()["content-type"].first, "application/json")
        let rawRequest2 = try client2.createAWSRequest(operation: "test", path: "/", httpMethod: "POST", input: object2)
        XCTAssertEqual(rawRequest2.getHttpHeaders()["content-type"].first, "binary/octet-stream")

        let client3 = createAWSClient(serviceProtocol: .query)
        let request3 = try client3.createAWSRequest(operation: "test", path: "/", httpMethod: "POST", input: object)
        XCTAssertEqual(request3.getHttpHeaders()["content-type"].first, "application/x-www-form-urlencoded; charset=utf-8")

        let client4 = createAWSClient(serviceProtocol: .ec2)
        let request4 = try client4.createAWSRequest(operation: "test", path: "/", httpMethod: "POST", input: object)
        XCTAssertEqual(request4.getHttpHeaders()["content-type"].first, "application/x-www-form-urlencoded; charset=utf-8")

        let client5 = createAWSClient(serviceProtocol: .restxml)
        let request5 = try client5.createAWSRequest(operation: "test", path: "/", httpMethod: "POST", input: object)
        XCTAssertEqual(request5.getHttpHeaders()["content-type"].first, "application/octet-stream")
    }

    func testHeaderEncoding() {
        struct Input: AWSEncodableShape {
            static let _encoding = [AWSMemberEncoding(label: "h", location: .header(locationName: "header-member"))]
            let h: String
        }
        let client = createAWSClient()
        do {
            let input = Input(h: "TestHeader")
            let request = try client.createAWSRequest(operation: "Test", path: "/", httpMethod: "GET", input: input)
            XCTAssertEqual(request.httpHeaders["header-member"] as? String, "TestHeader")
        } catch {
            XCTFail("\(error)")
        }
    }

    func testQueryEncoding() {
        struct Input: AWSEncodableShape {
            static let _encoding = [AWSMemberEncoding(label: "q", location: .querystring(locationName: "query"))]
            let q: String
        }
        let client = createAWSClient()
        do {
            let input = Input(q: "=3+5897^sdfjh&")
            let request = try client.createAWSRequest(operation: "Test", path: "/", httpMethod: "GET", input: input)
            XCTAssertEqual(request.url.absoluteString, "https://testService.us-east-1.amazonaws.com/?query=%3D3%2B5897%5Esdfjh%26")
        } catch {
            XCTFail("\(error)")
        }
    }

    func testQueryEncodedArray() {
        struct Input: AWSEncodableShape {
            static let _encoding = [AWSMemberEncoding(label: "q", location: .querystring(locationName: "query"))]
            let q: [String]
        }
        let client = createAWSClient()
        do {
            let input = Input(q: ["=3+5897^sdfjh&", "test"])
            let request = try client.createAWSRequest(operation: "Test", path: "/", httpMethod: "GET", input: input)
            XCTAssertEqual(request.url.absoluteString, "https://testService.us-east-1.amazonaws.com/?query=%3D3%2B5897%5Esdfjh%26&query=test")
        } catch {
            XCTFail("\(error)")
        }
    }

    func testQueryEncodedDictionary() {
        struct Input: AWSEncodableShape {
            static let _encoding = [AWSMemberEncoding(label: "q", location: .querystring(locationName: "query"))]
            let q: [String: Int]
        }
        let client = createAWSClient(region: .useast2, service: "myservice")
        do {
            let input = Input(q: ["one": 1, "two": 2])
            let request = try client.createAWSRequest(operation: "Test", path: "/", httpMethod: "GET", input: input)
            XCTAssertEqual(request.url.absoluteString, "https://myservice.us-east-2.amazonaws.com/?one=1&two=2")
        } catch {
            XCTFail("\(error)")
        }
    }

    func testURIEncoding() {
        struct Input: AWSEncodableShape {
            static let _encoding = [AWSMemberEncoding(label: "u", location: .uri(locationName: "key"))]
            let u: String
        }
        let client = createAWSClient(region: .cacentral1, service: "s3")
        do {
            let input = Input(u: "MyKey")
            let request = try client.createAWSRequest(operation: "Test", path: "/{key}", httpMethod: "GET", input: input)
            XCTAssertEqual(request.url.absoluteString, "https://s3.ca-central-1.amazonaws.com/MyKey")
        } catch {
            XCTFail("\(error)")
        }
    }

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
        let queryClient = createAWSClient(serviceProtocol: .query)
        do {
            let result: Output = try queryClient.validate(operation: "Test", response: response)
            XCTAssertEqual(result.h, "test-header")
        } catch {
            XCTFail("\(error)")
        }

        // JSON
        let jsonClient = createAWSClient(serviceProtocol: .restjson)
        do {
            let result: Output = try jsonClient.validate(operation: "Test", response: response)
            XCTAssertEqual(result.h, "test-header")
        } catch {
            XCTFail("\(error)")
        }
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
        let xmlClient = createAWSClient(serviceProtocol: .restxml)
        do {
            let result: Output = try xmlClient.validate(operation: "Test", response: response)
            XCTAssertEqual(result.status, 200)
        } catch {
            XCTFail("\(error)")
        }
        // JSON
        let jsonClient = createAWSClient(serviceProtocol: .restjson)
        do {
            let result: Output = try jsonClient.validate(operation: "Test", response: response)
            XCTAssertEqual(result.status, 200)
        } catch {
            XCTFail("\(error)")
        }
    }

    func testCreateWithXMLNamespace() {
        struct Input: AWSEncodableShape {
            public static let _xmlNamespace: String? = "https://test.amazonaws.com/doc/2020-03-11/"
            let number: Int
        }
        let xmlClient = createAWSClient(serviceProtocol: .restxml)
        do {
            let input = Input(number: 5)
            let request = try xmlClient.createAWSRequest(operation: "Test", path: "/", httpMethod: "GET", input: input)
            if case .xml(let element) = request.body {
                XCTAssertEqual(element.xmlString, "<Input xmlns=\"https://test.amazonaws.com/doc/2020-03-11/\"><number>5</number></Input>")
            } else {
                XCTFail("Shouldn't get here")
            }
        } catch {
            XCTFail("\(error)")
        }
    }


    func testCreateWithPayloadAndXMLNamespace() {
        struct Payload: AWSEncodableShape {
            public static let _xmlNamespace: String? = "https://test.amazonaws.com/doc/2020-03-11/"
            let number: Int
        }
        struct Input: AWSEncodableShape & AWSShapeWithPayload {
            public static let payloadPath: String = "payload"
            let payload: Payload
        }
        let xmlClient = createAWSClient(serviceProtocol: .restxml)
        do {
            let input = Input(payload: Payload(number: 5))
            let request = try xmlClient.createAWSRequest(operation: "Test", path: "/", httpMethod: "GET", input: input)
            if case .xml(let element) = request.body {
                XCTAssertEqual(element.xmlString, "<Payload xmlns=\"https://test.amazonaws.com/doc/2020-03-11/\"><number>5</number></Payload>")
            } else {
                XCTFail("Shouldn't get here")
            }
        } catch {
            XCTFail("\(error)")
        }
    }

    func testValidateXMLResponse() {
        class Output : AWSDecodableShape {
            let name : String
        }
        let xmlClient = createAWSClient(serviceProtocol: .restxml)
        let responseBody = "<Output><name>hello</name></Output>"
        let awsHTTPResponse = AWSHTTPResponseImpl(
            status: .ok,
            headers: HTTPHeaders(),
            bodyData: responseBody.data(using: .utf8)!
        )
        do {
            let output : Output = try xmlClient.validate(operation: "Output", response: awsHTTPResponse)
            XCTAssertEqual(output.name, "hello")
        } catch {
            XCTFail(error.localizedDescription)
        }
    }

    func testValidateXMLCodablePayloadResponse() {
        class Output : AWSDecodableShape & AWSShapeWithPayload {
            static let _encoding = [AWSMemberEncoding(label: "contentType", location: .header(locationName: "content-type"))]
            static let payloadPath: String = "name"
            let name : String
            let contentType: String

            private enum CodingKeys: String, CodingKey {
                case name = "name"
                case contentType = "content-type"
            }
        }
        let xmlClient = createAWSClient(serviceProtocol: .restxml)
        let response = AWSHTTPResponseImpl(
            status: .ok,
            headers: ["Content-Type":"application/json"],
            bodyData: "<name>hello</name>".data(using: .utf8)!
        )
        do {
            let output : Output = try xmlClient.validate(operation: "Output", response: response)
            XCTAssertEqual(output.name, "hello")
            XCTAssertEqual(output.contentType, "application/json")
        } catch {
            XCTFail(error.localizedDescription)
        }
    }

    func testValidateXMLRawPayloadResponse() {
        class Output : AWSDecodableShape, AWSShapeWithPayload {
            static let payloadPath: String = "body"
            public static var _encoding = [
                AWSMemberEncoding(label: "body", encoding: .blob)
            ]
            let body : AWSPayload
        }
        let xmlClient = createAWSClient(serviceProtocol: .restxml)
        let response = AWSHTTPResponseImpl(
            status: .ok,
            headers: HTTPHeaders(),
            bodyData: "{\"name\":\"hello\"}".data(using: .utf8)!
        )
        do {
            let output : Output = try xmlClient.validate(operation: "Output", response: response)
            XCTAssertEqual(output.body.asData(), "{\"name\":\"hello\"}".data(using: .utf8))
        } catch {
            XCTFail(error.localizedDescription)
        }
    }

    func testXMLError() {
        let response = AWSHTTPResponseImpl(
            status: .notFound,
            headers: HTTPHeaders(),
            bodyData: "<Error><Code>NoSuchKey</Code><Message>It doesn't exist</Message></Error>".data(using: .utf8)!
        )
        let xmlClient = createAWSClient(serviceProtocol: .restxml, possibleErrorTypes: [ServiceErrorType.self])
        let error = xmlClient.createError(for: response)
        if case ServiceErrorType.noSuchKey(let message) = error {
            XCTAssertEqual(message, "It doesn't exist")
        } else {
            XCTFail("Error is not noSuchKey")
        }
    }

    func testQueryError() {
        let response = AWSHTTPResponseImpl(
            status: .notFound,
            headers: HTTPHeaders(),
            bodyData: "<ErrorResponse><Error><Code>MessageRejected</Code><Message>Don't like it</Message></Error></ErrorResponse>".data(using: .utf8)!
        )
        let queryClient = createAWSClient(serviceProtocol: .query, possibleErrorTypes: [ServiceErrorType.self])
        let error = queryClient.createError(for: response)
        if case ServiceErrorType.messageRejected(let message) = error {
            XCTAssertEqual(message, "Don't like it")
        } else {
            XCTFail("Creating the wrong error")
        }
    }


    func testValidateJSONResponse() {
        class Output : AWSDecodableShape {
            let name : String
        }
        let response = AWSHTTPResponseImpl(
            status: .ok,
            headers: HTTPHeaders(),
            bodyData: "{\"name\":\"hello\"}".data(using: .utf8)!
        )
        let jsonClient = createAWSClient(serviceProtocol: .json(version: "1.1"))
        do {
            let output : Output = try jsonClient.validate(operation: "Output", response: response)
            XCTAssertEqual(output.name, "hello")
        } catch {
            XCTFail(error.localizedDescription)
        }
    }

    func testValidateJSONCodablePayloadResponse() {
        class Output2 : AWSDecodableShape {
            let name : String
        }
        struct Output : AWSDecodableShape & AWSShapeWithPayload {
            static let payloadPath: String = "output2"
            let output2 : Output2
        }
        let jsonClient = createAWSClient(serviceProtocol: .json(version: "1.1"))
        let response = AWSHTTPResponseImpl(
            status: .ok,
            headers: HTTPHeaders(),
            bodyData: "{\"name\":\"hello\"}".data(using: .utf8)!
        )
        do {
            let output : Output = try jsonClient.validate(operation: "Output", response: response)
            XCTAssertEqual(output.output2.name, "hello")
        } catch {
            XCTFail(error.localizedDescription)
        }
    }

    func testValidateJSONRawPayloadResponse() {
        struct Output : AWSDecodableShape, AWSShapeWithPayload {
            static let payloadPath: String = "body"
            public static var _encoding = [
                AWSMemberEncoding(label: "contentType", location: .header(locationName: "content-type")),
                AWSMemberEncoding(label: "body", encoding: .blob)
            ]
            let body : AWSPayload
        }
        let jsonClient = createAWSClient(serviceProtocol: .json(version: "1.1"))
        let response = AWSHTTPResponseImpl(
            status: .ok,
            headers: ["Content-Type":"application/json"],
            bodyData: "{\"name\":\"hello\"}".data(using: .utf8)!
        )
        do {
            let output : Output = try jsonClient.validate(operation: "Output", response: response)
            XCTAssertEqual(output.body.asData(), "{\"name\":\"hello\"}".data(using: .utf8))
        } catch {
            XCTFail(error.localizedDescription)
        }
    }

    func testJSONError() {
        let response = AWSHTTPResponseImpl(
            status: .notFound,
            headers: HTTPHeaders(),
            bodyData: "{\"__type\":\"ResourceNotFoundException\", \"message\": \"Donald Where's Your Troosers?\"}".data(using: .utf8)!
        )
        let jsonClient = createAWSClient(serviceProtocol: .json(version: "1.1"), possibleErrorTypes: [ServiceErrorType.self])
        let error = jsonClient.createError(for: response)
        if case ServiceErrorType.resourceNotFoundException(let message) = error {
            XCTAssertEqual(message, "Donald Where's Your Troosers?")
        } else {
            XCTFail("Error is not resourceNotFoundException")
        }
    }


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
        let jsonClient = createAWSClient(serviceProtocol: .json(version: "1.1"))
        var buffer = ByteBufferAllocator().buffer(capacity: 0)
        buffer.writeString(
            """
            {"_embedded": {"a": [{"s":"Hello", "i":1234}, {"s":"Hello2", "i":12345}]}, "d":3.14, "b":true}
            """
        )
        let response = HTTPClient.Response(
            host: "localhost",
            status: .ok,
            headers: ["Content-Type":"application/hal+json"],
            body: buffer
        )
        do {
            let output : Output2 = try jsonClient.validate(operation: "Output", response: response)
            XCTAssertEqual(output.a.count, 2)
            XCTAssertEqual(output.d, 3.14)
            XCTAssertEqual(output.a[1].s, "Hello2")
        } catch {
            XCTFail(error.localizedDescription)
        }
    }

    func testDataInJsonPayload() {
        struct DataContainer: AWSEncodableShape {
            let data: Data
        }
        struct J: AWSEncodableShape & AWSShapeWithPayload {
            public static let payloadPath: String = "dataContainer"
            let dataContainer: DataContainer
        }
        let jsonClient = createAWSClient(serviceProtocol: .json(version: "1.1"))
        let input = J(dataContainer: DataContainer(data: Data("test data".utf8)))
        do {
            _ = try jsonClient.createAWSRequest(
                operation: "PutRecord",
                path: "/",
                httpMethod: "POST",
                input: input
            )
        } catch {
            XCTFail(error.localizedDescription)
        }
    }

    func testPayloadDataInResponse() {
        struct Response: AWSDecodableShape, AWSShapeWithPayload {
            public static let payloadPath: String = "payload"
            public static var _encoding = [
                AWSMemberEncoding(label: "payload", encoding: .blob),
            ]
            let payload: AWSPayload
        }
        let jsonClient = createAWSClient(serviceProtocol: .json(version: "1.1"))
        var buffer = ByteBufferAllocator().buffer(capacity: 0)
        buffer.writeString("TestString")
        let response = HTTPClient.Response(
            host: "localhost",
            status: .ok,
            headers: ["Content-Type":"application/hal+json"],
            body: buffer
        )
        do {
            let output : Response = try jsonClient.validate(operation: "Output", response: response)
            XCTAssertEqual(output.payload.asString(), "TestString")
        } catch {
            XCTFail(error.localizedDescription)
        }
    }

    func testClientNoInputNoOutput() {
        do {
            let awsServer = AWSTestServer(serviceProtocol: .json)
            let client = createAWSClient(accessKeyId: "", secretAccessKey: "", serviceProtocol: .json(version: "1.1"), endpoint: awsServer.address)
            let response = client.send(operation: "test", path: "/", httpMethod: "POST")

            try awsServer.processRaw { request in
                let response = AWSTestServer.Response(httpStatus: .ok, headers: [:], body: nil)
                return .result(response)
            }

            try response.wait()
            try awsServer.stop()
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testClientWithInputNoOutput() {
        enum InputEnum: String, Codable {
            case first
            case second
        }
        struct Input : AWSEncodableShape & Decodable {
            let e: InputEnum
            let i: [Int64]
        }

        do {
            let awsServer = AWSTestServer(serviceProtocol: .json)
            let client = createAWSClient(accessKeyId: "", secretAccessKey: "", serviceProtocol: .json(version: "1.1"), endpoint: awsServer.address)
            let input = Input(e:.second, i: [1,2,4,8])
            let response = client.send(operation: "test", path: "/", httpMethod: "POST", input: input)

            try awsServer.processRaw { request in
                let receivedInput = try JSONDecoder().decode(Input.self, from: request.body)
                XCTAssertEqual(receivedInput.e, .second)
                XCTAssertEqual(receivedInput.i, [1,2,4,8])
                let response = AWSTestServer.Response(httpStatus: .ok, headers: [:], body: nil)
                return .result(response)
            }

            try response.wait()
            try awsServer.stop()
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testClientNoInputWithOutput() {
        struct Output : AWSDecodableShape & Encodable {
            let s: String
            let i: Int64
        }
        do {
            let awsServer = AWSTestServer(serviceProtocol: .json)
            let client = createAWSClient(accessKeyId: "", secretAccessKey: "", serviceProtocol: .json(version: "1.1"), endpoint: awsServer.address)
            let response: EventLoopFuture<Output> = client.send(operation: "test", path: "/", httpMethod: "POST")

            try awsServer.processRaw { request in
                let output = Output(s: "TestOutputString", i: 547)
                let byteBuffer = try JSONEncoder().encodeAsByteBuffer(output, allocator: ByteBufferAllocator())
                let response = AWSTestServer.Response(httpStatus: .ok, headers: [:], body: byteBuffer)
                return .result(response)
            }

            let output = try response.wait()

            XCTAssertEqual(output.s, "TestOutputString")
            XCTAssertEqual(output.i, 547)
            try awsServer.stop()
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testEC2ClientRequest() {
        struct Input: AWSEncodableShape {
            let array: [String]
        }
        let client = createAWSClient(serviceProtocol: .ec2, apiVersion: "2013-12-02")
        do {
            let input = Input(array: ["entry1", "entry2"])
            let request = try client.createAWSRequest(operation: "Test", path: "/", httpMethod: "GET", input: input)
            XCTAssertEqual(request.body.asString(), "Action=Test&Array.1=entry1&Array.2=entry2&Version=2013-12-02")
        } catch {
            XCTFail("\(error)")
        }
    }

    func testEC2ValidateError() {
        let response = AWSHTTPResponseImpl(
            status: .notFound,
            headers: HTTPHeaders(),
            bodyData: "<Errors><Error><Code>NoSuchKey</Code><Message>It doesn't exist</Message></Error></Errors>".data(using: .utf8)!
        )
        let client = createAWSClient(serviceProtocol: .ec2)
        if let error = client.createError(for: response) as? AWSResponseError {
            XCTAssertEqual(error.errorCode, "NoSuchKey")
            XCTAssertEqual(error.message, "It doesn't exist")
        } else {
            XCTFail("Throwing the wrong error")
        }
    }

    func testRequestStreaming() {
        struct Input : AWSEncodableShape & AWSShapeWithPayload {
            static var payloadPath: String = "payload"
            static var options: PayloadOptions = [.allowStreaming]
            let payload: AWSPayload
            private enum CodingKeys: CodingKey {}
        }

        let awsServer = AWSTestServer(serviceProtocol: .json)
        let httpClient = HTTPClient(eventLoopGroupProvider: .createNew)
        defer {
            XCTAssertNoThrow(try awsServer.stop())
            XCTAssertNoThrow(try httpClient.syncShutdown())
        }
        do {
            let client = createAWSClient(accessKeyId: "", secretAccessKey: "", endpoint: awsServer.address, httpClientProvider: .shared(httpClient))

            // supply buffer in 16k blocks
            let bufferSize = 1024*1024
            let blockSize = 16*1024
            let data = createRandomBuffer(45,9182, size: bufferSize)

            var i = 0
            let payload = AWSPayload.stream(size: bufferSize) { eventLoop in
                var buffer = ByteBufferAllocator().buffer(capacity: blockSize)
                buffer.writeBytes(data[i..<(i+blockSize)])
                i = i + blockSize
                return eventLoop.makeSucceededFuture(buffer)
            }
            let input = Input(payload: payload)
            let response = client.send(operation: "test", path: "/", httpMethod: "POST", input: input)

            try awsServer.processRaw { request in
                let bytes = request.body.getBytes(at: 0, length: request.body.readableBytes)
                XCTAssertEqual(bytes, data)
                let response = AWSTestServer.Response(httpStatus: .ok, headers: [:], body: nil)
                return .result(response)
            }

            try response.wait()
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testRequestStreamingTooMuchData() {
        struct Input : AWSEncodableShape & AWSShapeWithPayload {
            static var payloadPath: String = "payload"
            static var options: PayloadOptions = [.allowStreaming]
            let payload: AWSPayload
            private enum CodingKeys: CodingKey {}
        }

        let awsServer = AWSTestServer(serviceProtocol: .json)
        let httpClient = HTTPClient(eventLoopGroupProvider: .createNew)
        defer {
            try? awsServer.stop()
            XCTAssertNoThrow(try httpClient.syncShutdown())
        }
        do {
            let client = createAWSClient(accessKeyId: "", secretAccessKey: "", endpoint: awsServer.address, httpClientProvider: .shared(httpClient))

            // set up stream of 8 bytes but supply more than that
            let payload = AWSPayload.stream(size: 8) { eventLoop in
                var buffer = ByteBufferAllocator().buffer(capacity: 0)
                buffer.writeString("String longer than 8 bytes")
                return eventLoop.makeSucceededFuture(buffer)
            }
            let input = Input(payload: payload)
            let response = client.send(operation: "test", path: "/", httpMethod: "POST", input: input)
            try response.wait()
        } catch AWSClient.ClientError.tooMuchData {
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testRequestStreamingFile() {
        struct Input : AWSEncodableShape & AWSShapeWithPayload {
            static var payloadPath: String = "payload"
            static var options: PayloadOptions = [.allowStreaming]
            let payload: AWSPayload
            private enum CodingKeys: CodingKey {}
        }

        let awsServer = AWSTestServer(serviceProtocol: .json)
        let httpClient = HTTPClient(eventLoopGroupProvider: .createNew)
        defer {
            try? awsServer.stop()
            XCTAssertNoThrow(try httpClient.syncShutdown())
        }
        do {
            let client = createAWSClient(accessKeyId: "", secretAccessKey: "", endpoint: awsServer.address, httpClientProvider: .shared(httpClient))

            let bufferSize = 208*1024
            let data = Data(createRandomBuffer(45,9182, size: bufferSize))
            let filename = "testRequestStreamingFile"
            let fileURL = URL(fileURLWithPath: filename)
            try data.write(to: fileURL)
            defer {
                XCTAssertNoThrow(try FileManager.default.removeItem(at: fileURL))
            }

            let threadPool = NIOThreadPool(numberOfThreads: 3)
            threadPool.start()
            let fileIO = NonBlockingFileIO(threadPool: threadPool)
            let fileHandle = try fileIO.openFile(path: filename, mode: .read, eventLoop: httpClient.eventLoopGroup.next()).wait()
            defer {
                XCTAssertNoThrow(try fileHandle.close())
                XCTAssertNoThrow(try threadPool.syncShutdownGracefully())
            }

            let input = Input(payload: .fileHandle(fileHandle, size: bufferSize, fileIO: fileIO))
            let response = client.send(operation: "test", path: "/", httpMethod: "POST", input: input)

            try awsServer.processRaw { request in
                XCTAssertNil(request.headers["transfer-encoding"])
                XCTAssertEqual(request.headers["Content-Length"], bufferSize.description)
                let requestData = request.body.getData(at: 0, length: request.body.readableBytes)
                XCTAssertEqual(requestData, data)
                let response = AWSTestServer.Response(httpStatus: .ok, headers: [:], body: nil)
                return .result(response)
            }

            try response.wait()
        } catch AWSClient.ClientError.tooMuchData {
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testRequestChunkedStreaming() {
        struct Input : AWSEncodableShape & AWSShapeWithPayload {
            static var payloadPath: String = "payload"
            static var options: PayloadOptions = [.allowStreaming, .allowChunkedStreaming]
            let payload: AWSPayload
            private enum CodingKeys: CodingKey {}
        }

        let awsServer = AWSTestServer(serviceProtocol: .json)
        let httpClient = HTTPClient(eventLoopGroupProvider: .createNew)
        defer {
            XCTAssertNoThrow(try awsServer.stop())
            XCTAssertNoThrow(try httpClient.syncShutdown())
        }
        do {
            let client = createAWSClient(accessKeyId: "", secretAccessKey: "", endpoint: awsServer.address, httpClientProvider: .shared(httpClient))

            // supply buffer in 16k blocks
            let bufferSize = 145*1024
            let blockSize = 16*1024
            let data = createRandomBuffer(45,9182, size: bufferSize)
            var byteBuffer = ByteBufferAllocator().buffer(capacity: bufferSize)
            byteBuffer.writeBytes(data)

            let payload = AWSPayload.stream { eventLoop in
                let size = min(blockSize, byteBuffer.readableBytes)
                if size == 0 {
                    return eventLoop.makeSucceededFuture((byteBuffer))
                } else {
                    return eventLoop.makeSucceededFuture(byteBuffer.readSlice(length: size)!)
                }
            }
            let input = Input(payload: payload)
            let response = client.send(operation: "test", path: "/", httpMethod: "POST", input: input)

            try awsServer.processRaw { request in
                let bytes = request.body.getBytes(at: 0, length: request.body.readableBytes)
                XCTAssertTrue(bytes == data)
                let response = AWSTestServer.Response(httpStatus: .ok, headers: [:], body: nil)
                return .result(response)
            }

            try response.wait()
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testProvideHTTPClient() {
        do {
            // By default AsyncHTTPClient will follow redirects. This test creates an HTTP client that doesn't follow redirects and
            // provides it to AWSClient
            let awsServer = AWSTestServer(serviceProtocol: .json)
            let httpClientConfig = AsyncHTTPClient.HTTPClient.Configuration(redirectConfiguration: .init(.disallow))
            let httpClient = AsyncHTTPClient.HTTPClient(eventLoopGroupProvider: .createNew, configuration: httpClientConfig)
            defer {
                XCTAssertNoThrow(try awsServer.stop())
                XCTAssertNoThrow(try httpClient.syncShutdown())
            }
            let client = createAWSClient(accessKeyId: "", secretAccessKey: "", serviceProtocol: .json(version: "1.1"), endpoint: awsServer.address, httpClientProvider: .shared(httpClient))
            let response = client.send(operation: "test", path: "/", httpMethod: "POST")

            try awsServer.processRaw { request in
                let response = AWSTestServer.Response(httpStatus: .temporaryRedirect, headers: ["Location":awsServer.address], body: nil)
                return .result(response)
            }

            try response.wait()
            XCTFail("Shouldn't get here as the provided client doesn't follow redirects")
        } catch let error as AWSError {
            XCTAssertEqual(error.message, "Unhandled Error")
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testRegionEnum() {
        let region = Region(rawValue: "my-region")
        if Region.other("my-region") == region {
            XCTAssertEqual(region.rawValue, "my-region")
        } else {
            XCTFail("Did not construct Region.other()")
        }
    }

    func testServerError() {
        do {
            let httpClient = AsyncHTTPClient.HTTPClient(eventLoopGroupProvider: .createNew)
            let awsServer = AWSTestServer(serviceProtocol: .json)
            defer {
                XCTAssertNoThrow(try awsServer.stop())
                XCTAssertNoThrow(try httpClient.syncShutdown())
            }
            let client = createAWSClient(accessKeyId: "", secretAccessKey: "", serviceProtocol: .json(version: "1.1"), endpoint: awsServer.address, retryPolicy: ExponentialRetry(base: .milliseconds(200)), httpClientProvider: .shared(httpClient))
            let response = client.send(operation: "test", path: "/", httpMethod: "POST")

            var count = 0
            try awsServer.processRaw { request in
                count += 1
                if count < 5 {
                    return .error(.internal, continueProcessing: true)
                } else {
                    return .result(.ok)
                }
            }

            try response.wait()
        } catch let error as AWSServerError {
            switch error {
            case .internalFailure:
                XCTAssertEqual(error.message, AWSTestServer.ErrorType.internal.message)
            default:
                XCTFail("Unexpected error: \(error)")
            }
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testClientRetry() {
        struct Output : AWSDecodableShape, Encodable {
            let s: String
        }
        do {
            let httpClient = AsyncHTTPClient.HTTPClient(eventLoopGroupProvider: .createNew)
            let awsServer = AWSTestServer(serviceProtocol: .json)
            defer {
                XCTAssertNoThrow(try awsServer.stop())
                XCTAssertNoThrow(try httpClient.syncShutdown())
            }
            let client = createAWSClient(
                accessKeyId: "",
                secretAccessKey: "",
                serviceProtocol: .json(version: "1.1"),
                endpoint: awsServer.address,
                retryPolicy: JitterRetry(),
                httpClientProvider: .shared(httpClient)
            )
            let response: EventLoopFuture<Output> = client.send(operation: "test", path: "/", httpMethod: "POST")

            var count = 0
            try awsServer.processRaw { request in
                count += 1
                if count < 3 {
                    return .error(.notImplemented, continueProcessing: true)
                } else {
                    let output = Output(s: "TestOutputString")
                    let byteBuffer = try JSONEncoder().encodeAsByteBuffer(output, allocator: ByteBufferAllocator())
                    let response = AWSTestServer.Response(httpStatus: .ok, headers: [:], body: byteBuffer)
                    return .result(response)
                }
            }

            let output = try response.wait()

            XCTAssertEqual(output.s, "TestOutputString")
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testClientRetryFail() {
        struct Output : AWSDecodableShape, Encodable {
            let s: String
        }
        do {
            let httpClient = AsyncHTTPClient.HTTPClient(eventLoopGroupProvider: .createNew)
            let awsServer = AWSTestServer(serviceProtocol: .json)
            defer {
                XCTAssertNoThrow(try awsServer.stop())
                XCTAssertNoThrow(try httpClient.syncShutdown())
            }
            let client = createAWSClient(
                accessKeyId: "",
                secretAccessKey: "",
                serviceProtocol: .json(version: "1.1"),
                endpoint: awsServer.address,
                retryPolicy: JitterRetry(),
                httpClientProvider: .shared(httpClient)
            )
            let response: EventLoopFuture<Output> = client.send(operation: "test", path: "/", httpMethod: "POST")

            try awsServer.processRaw { request in
                return .error(.accessDenied, continueProcessing: false)
            }

            let output = try response.wait()

            XCTAssertEqual(output.s, "TestOutputString")
        } catch  let error as AWSClientError where error == AWSClientError.accessDenied {
            XCTAssertEqual(error.message, AWSTestServer.ErrorType.accessDenied.message)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testClientResponseEventLoop() {
        do {
            let eventLoopGroup = MultiThreadedEventLoopGroup(numberOfThreads: 5)
            let httpClient = HTTPClient(eventLoopGroupProvider: .shared(eventLoopGroup))
            let awsServer = AWSTestServer(serviceProtocol: .json)
            defer {
                XCTAssertNoThrow(try httpClient.syncShutdown())
                XCTAssertNoThrow(try eventLoopGroup.syncShutdownGracefully())
                XCTAssertNoThrow(try awsServer.stop())
            }
            let client = createAWSClient(
                accessKeyId: "",
                secretAccessKey: "",
                endpoint: awsServer.address,
                httpClientProvider: .shared(httpClient)
            )
            let eventLoop = client.eventLoopGroup.next()
            let response: EventLoopFuture<Void> = client.send(operation: "test", path: "/", httpMethod: "POST", on: eventLoop)

            try awsServer.processRaw { request in
                return .result(.ok)
            }
            XCTAssertTrue(eventLoop === response.eventLoop)

            try response.wait()
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testMiddlewareIsOnlyAppliedOnce() throws {
        struct URLAppendMiddleware: AWSServiceMiddleware {
            func chain(request: AWSRequest) throws -> AWSRequest {
                var request = request
                request.url.appendPathComponent("test")
                return request
            }
        }
        let client = createAWSClient(middlewares: [URLAppendMiddleware()])
        let request = try client.createAWSRequest(operation: "test", path: "/", httpMethod: "GET")
        XCTAssertEqual(request.url.absoluteString, "https://testService.us-east-1.amazonaws.com/test")
    }
}

/// Error enum for Kinesis
public enum ServiceErrorType: AWSErrorType {
    case resourceNotFoundException(message: String?)
    case noSuchKey(message: String?)
    case messageRejected(message: String?)
}

extension ServiceErrorType {
    public init?(errorCode: String, message: String?){
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

    public var description : String {
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

