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

    static var allTests : [(String, (AWSClientTests) -> () throws -> Void)] {
        return [
            ("testGetCredential", testGetCredential),
            ("testExpiredCredential", testExpiredCredential),
            ("testCreateAWSRequest", testCreateAWSRequest),
            ("testCreateNIORequest", testCreateNIORequest),
            ("testValidateCode", testValidateCode),
            ("testUnsignedClient", testUnsignedClient),
            ("testHeaderEncoding", testHeaderEncoding),
            ("testQueryEncoding", testQueryEncoding),
            ("testURIEncoding", testURIEncoding),
            ("testValidateXMLResponse", testValidateXMLResponse),
            ("testValidateXMLCodablePayloadResponse", testValidateXMLCodablePayloadResponse),
            ("testValidateXMLRawPayloadResponse", testValidateXMLRawPayloadResponse),
            ("testValidateXMLError", testValidateXMLError),
            ("testValidateRawResponseError", testValidateRawResponseError),
            ("testValidateQueryError", testValidateQueryError),
            ("testValidateJSONResponse", testValidateJSONResponse),
            ("testValidateJSONCodablePayloadResponse", testValidateJSONCodablePayloadResponse),
            ("testValidateJSONRawPayloadResponse", testValidateJSONRawPayloadResponse),
            ("testValidateJSONError", testValidateJSONError),
            ("testProcessHAL", testProcessHAL),
            ("testDataInJsonPayload", testDataInJsonPayload),
            ("testPayloadDataInResponse", testPayloadDataInResponse),
            ("testClientNoInputNoOutput", testClientNoInputNoOutput),
            ("testClientWithInputNoOutput", testClientWithInputNoOutput),
            ("testClientNoInputWithOutput", testClientNoInputWithOutput),
            ("testEC2ClientRequest", testEC2ClientRequest),
            ("testEC2ValidateError", testEC2ValidateError)
        ]
    }

    struct C: AWSShape {
        public static var _encoding: [AWSMemberEncoding] = [
             AWSMemberEncoding(label: "value", location: .header(locationName: "value"))
        ]
        let value = "<html><body><a href=\"https://redsox.com\">Test</a></body></html>"

        private enum CodingKeys: String, CodingKey {
            case value = "Value"
        }
    }

    struct E: AWSShape {
        let Member = ["memberKey": "memberValue", "memberKey2" : "memberValue2"]

        private enum CodingKeys: String, CodingKey {
            case Member = "Member"
        }
    }

    struct F: AWSShape {
        public static let payloadPath: String? = "fooParams"

        public let fooParams: E?

        public init(fooParams: E? = nil) {
            self.fooParams = fooParams
        }

        private enum CodingKeys: String, CodingKey {
            case fooParams = "fooParams"
        }
    }


    func testGetCredential() {
        let sesClient = AWSClient(
            accessKeyId: "key",
            secretAccessKey: "secret",
            region: nil,
            service: "email",
            serviceProtocol: ServiceProtocol(type: .query),
            apiVersion: "2013-12-01",
            middlewares: [],
            httpClientProvider: .createNew
        )

        do {
            let credentialForSignature = try sesClient.credentialProvider.getCredential().wait()
            XCTAssertEqual(credentialForSignature.accessKeyId, "key")
            XCTAssertEqual(credentialForSignature.secretAccessKey, "secret")
        } catch {
            XCTFail(error.localizedDescription)
        }
    }

    // this test only really works on Linux as it requires the MetaDataService. On mac it will just pass automatically
    func testExpiredCredential() {
        let client = AWSClient(
            region: .useast1,
            service: "email",
            serviceProtocol: ServiceProtocol(type: .query),
            apiVersion: "2013-12-01",
            httpClientProvider: .createNew)

        do {
            let credentials = try client.credentialProvider.getCredential().wait()
            print(credentials)
        } catch NIO.ChannelError.connectTimeout(_) {
            // credentials request should fail. One possible error is a connectTimerout
        } catch is NIOConnectionError {
                // credentials request should fail. One possible error is a connection error
        } catch MetaDataServiceError.couldNotGetInstanceRoleName {
            // credentials request fails in a slightly different way if it finds the IP
        } catch {
            XCTFail("Unexpected error \(error)")
        }
    }

    let sesClient = AWSClient(
        accessKeyId: "foo",
        secretAccessKey: "bar",
        region: nil,
        service: "email",
        serviceProtocol: ServiceProtocol(type: .query),
        apiVersion: "2013-12-01",
        middlewares: [AWSLoggingMiddleware()],
        possibleErrorTypes: [SESErrorType.self],
        httpClientProvider: .createNew
    )

    let kinesisClient = AWSClient(
        accessKeyId: "foo",
        secretAccessKey: "bar",
        region: nil,
        amzTarget: "Kinesis_20131202",
        service: "kinesis",
        serviceProtocol: ServiceProtocol(type: .json, version: ServiceProtocol.Version(major: 1, minor: 1)),
        apiVersion: "2013-12-02",
        middlewares: [AWSLoggingMiddleware()],
        possibleErrorTypes: [KinesisErrorType.self],
        httpClientProvider: .createNew
    )

    let s3Client = AWSClient(
        accessKeyId: "foo",
        secretAccessKey: "bar",
        region: nil,
        service: "s3",
        serviceProtocol: ServiceProtocol(type: .restxml),
        apiVersion: "2006-03-01",
        endpoint: nil,
        serviceEndpoints: ["us-west-2": "s3.us-west-2.amazonaws.com", "eu-west-1": "s3.eu-west-1.amazonaws.com", "us-east-1": "s3.amazonaws.com", "ap-northeast-1": "s3.ap-northeast-1.amazonaws.com", "s3-external-1": "s3-external-1.amazonaws.com", "ap-southeast-2": "s3.ap-southeast-2.amazonaws.com", "sa-east-1": "s3.sa-east-1.amazonaws.com", "ap-southeast-1": "s3.ap-southeast-1.amazonaws.com", "us-west-1": "s3.us-west-1.amazonaws.com"],
        partitionEndpoint: "us-east-1",
        middlewares: [AWSLoggingMiddleware()],
        possibleErrorTypes: [S3ErrorType.self],
        httpClientProvider: .createNew
    )

    let ec2Client = AWSClient(
        accessKeyId: "foo",
        secretAccessKey: "bar",
        region: nil,
        service: "ec2",
        serviceProtocol: ServiceProtocol(type: .other("ec2")),
        apiVersion: "2013-12-02",
        middlewares: [AWSLoggingMiddleware()],
        httpClientProvider: .createNew
    )

    func testCreateAWSRequest() {
        let input1 = C()
        let input2 = E()
        let input3 = F(fooParams: input2)

        do {
            let awsRequest = try sesClient.createAWSRequest(
                operation: "SendEmail",
                path: "/",
                httpMethod: "POST",
                input: input1
            )
            XCTAssertEqual(awsRequest.url.absoluteString, "\(sesClient.endpoint)/")
            let nioRequest: AWSHTTPRequest = awsRequest.toHTTPRequest()
            XCTAssertEqual(nioRequest.headers["value"][0], "<html><body><a href=\"https://redsox.com\">Test</a></body></html>")
            XCTAssertEqual(nioRequest.headers["Content-Type"][0], "application/x-www-form-urlencoded; charset=utf-8")
            XCTAssertEqual(nioRequest.method, HTTPMethod.POST)
        } catch {
            XCTFail(error.localizedDescription)
        }

        let kinesisClient = AWSClient(
            accessKeyId: "foo",
            secretAccessKey: "bar",
            region: nil,
            amzTarget: "Kinesis_20131202",
            service: "kinesis",
            serviceProtocol: ServiceProtocol(type: .json, version: ServiceProtocol.Version(major: 1, minor: 1)),
            apiVersion: "2013-12-02",
            middlewares: [],
            possibleErrorTypes: [KinesisErrorType.self],
            httpClientProvider: .createNew
        )

        do {
            let awsRequest = try kinesisClient.createAWSRequest(
                operation: "PutRecord",
                path: "/",
                httpMethod: "POST",
                input: input2
            )
            XCTAssertEqual(awsRequest.url.absoluteString, "\(kinesisClient.endpoint)/")

            if case .json(let data) = awsRequest.body, let parsedBody = try JSONSerialization.jsonObject(with: data, options: []) as? [String:Any] {
                if let member = parsedBody["Member"] as? [String:Any] {
                    if let memberKey = member["memberKey"] {
                        XCTAssertEqual(String(describing: memberKey), "memberValue")
                    } else {
                        XCTFail("Cannot parse memberKey")
                    }
                    if let memberKey2 = member["memberKey2"] {
                        XCTAssertEqual(String(describing: memberKey2), "memberValue2")
                    } else {
                      XCTFail("Cannot parse memberKey2")
                    }
                }

            }

            let nioRequest: AWSHTTPRequest = awsRequest.toHTTPRequest()
            XCTAssertEqual(nioRequest.headers["Content-Type"][0], "application/x-amz-json-1.1")
            XCTAssertEqual(nioRequest.method, HTTPMethod.POST)
        } catch {
            XCTFail(error.localizedDescription)
        }

        do {
            let awsRequest = try s3Client.createAWSRequest(
                operation: "ListObjectsV2",
                path: "/Bucket?list-type=2",
                httpMethod: "GET",
                input: input1
            )

            XCTAssertEqual(awsRequest.url.absoluteString, "https://s3.amazonaws.com/Bucket?list-type=2")
            let nioRequest: AWSHTTPRequest = awsRequest.toHTTPRequest()
            XCTAssertEqual(nioRequest.method, HTTPMethod.GET)
            XCTAssertEqual(nioRequest.body, nil)
        } catch {
            XCTFail(error.localizedDescription)
        }

        // encode for restxml
        //
        do {
            let awsRequest = try s3Client.createAWSRequest(
                operation: "payloadPath",
                path: "/Bucket?list-type=2",
                httpMethod: "POST",
                input: input3
            )

            XCTAssertNotNil(awsRequest.body)
            if case .xml(let element) = awsRequest.body {
                let payload = try XMLDecoder().decode(E.self, from: element)
                XCTAssertEqual(payload.Member["memberKey2"], "memberValue2")
            }
            let nioRequest: AWSHTTPRequest = awsRequest.toHTTPRequest()
            XCTAssertEqual(nioRequest.method, HTTPMethod.POST)
        } catch {
            XCTFail(error.localizedDescription)
        }

        // encode for json
        //
        do {
            let awsRequest = try kinesisClient.createAWSRequest(
                operation: "PutRecord",
                path: "/",
                httpMethod: "POST",
                input: input3
            )
            XCTAssertNotNil(awsRequest.body)
            if case .json(let data) = awsRequest.body {
                let jsonBody = try! JSONSerialization.jsonObject(with: data, options: .allowFragments) as! [String:Any]
                let fromJson = jsonBody["Member"]! as! [String: String]
                XCTAssertEqual(fromJson["memberKey"], "memberValue")
            }

        } catch {
            XCTFail(error.localizedDescription)
        }
    }

    func testCreateAwsRequestWithKeywordInHeader() {
        struct KeywordRequest: AWSShape {
            static var _encoding: [AWSMemberEncoding] = [
                AWSMemberEncoding(label: "repeat", location: .header(locationName: "repeat")),
            ]
            let `repeat`: String
        }
        do {
            let request = KeywordRequest(repeat: "Repeat")
            let awsRequest = try s3Client.createAWSRequest(operation: "Keyword", path: "/", httpMethod: "POST", input: request)
            XCTAssertEqual(awsRequest.httpHeaders["repeat"] as? String, "Repeat")
            XCTAssertEqual(awsRequest.body.asByteBuffer(), nil)
        } catch {
            XCTFail(error.localizedDescription)
        }
    }

    func testCreateAwsRequestWithKeywordInQuery() {
        struct KeywordRequest: AWSShape {
            static var _encoding: [AWSMemberEncoding] = [
                AWSMemberEncoding(label: "self", location: .querystring(locationName: "self")),
            ]
            let `self`: String
        }
        do {
            let request = KeywordRequest(self: "KeywordRequest")
            let awsRequest = try s3Client.createAWSRequest(operation: "Keyword", path: "/", httpMethod: "POST", input: request)
            XCTAssertEqual(awsRequest.url, URL(string:"https://s3.amazonaws.com/?self=KeywordRequest")!)
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
            serviceProtocol: ServiceProtocol(type: .json, version: ServiceProtocol.Version(major: 1, minor: 1)),
            apiVersion: "2013-12-02",
            middlewares: [],
            possibleErrorTypes: [KinesisErrorType.self],
            httpClientProvider: .createNew
        )

        do {
            let awsRequest = try kinesisClient.createAWSRequest(
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
        let client = AWSClient(
            accessKeyId: "",
            secretAccessKey: "",
            region: .useast1,
            service: "s3",
            serviceProtocol: ServiceProtocol(type: .restxml),
            apiVersion: "2013-12-02",
            middlewares: [],
            httpClientProvider: .createNew
        )

        do {
            let awsRequest = try client.createAWSRequest(
                operation: "CopyObject",
                path: "/",
                httpMethod: "PUT",
                input: input
            )

            let request: AWSHTTPRequest = awsRequest.createHTTPRequest(signer: try client.signer.wait())

            XCTAssertNil(request.headers["Authorization"].first)
        } catch {
            XCTFail(error.localizedDescription)
        }
    }

    func testHeaderEncoding() {
        struct Input: AWSShape {
            static let _encoding = [AWSMemberEncoding(label: "h", location: .header(locationName: "header-member"))]
            let h: String
        }
        do {
            let input = Input(h: "TestHeader")
            let request = try kinesisClient.createAWSRequest(operation: "Test", path: "/", httpMethod: "GET", input: input)
            XCTAssertEqual(request.httpHeaders["header-member"] as? String, "TestHeader")
        } catch {
            XCTFail("\(error)")
        }
    }

    func testQueryEncoding() {
        struct Input: AWSShape {
            static let _encoding = [AWSMemberEncoding(label: "q", location: .querystring(locationName: "query"))]
            let q: String
        }
        do {
            let input = Input(q: "=3+5897^sdfjh&")
            let request = try kinesisClient.createAWSRequest(operation: "Test", path: "/", httpMethod: "GET", input: input)
            XCTAssertEqual(request.url.absoluteString, "https://kinesis.us-east-1.amazonaws.com/?query=%3D3%2B5897%5Esdfjh%26")
        } catch {
            XCTFail("\(error)")
        }
    }

    func testURIEncoding() {
        struct Input: AWSShape {
            static let _encoding = [AWSMemberEncoding(label: "u", location: .uri(locationName: "key"))]
            let u: String
        }
        do {
            let input = Input(u: "MyKey")
            let request = try s3Client.createAWSRequest(operation: "Test", path: "/{key}", httpMethod: "GET", input: input)
            XCTAssertEqual(request.url.absoluteString, "https://s3.amazonaws.com/MyKey")
        } catch {
            XCTFail("\(error)")
        }
    }

    func testCreateWithXMLNamespace() {
        struct Input: AWSShape {
            public static let _xmlNamespace: String? = "https://test.amazonaws.com/doc/2020-03-11/"
            let number: Int
        }
        do {
            let input = Input(number: 5)
            let request = try s3Client.createAWSRequest(operation: "Test", path: "/", httpMethod: "GET", input: input)
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
        struct Payload: AWSShape {
            public static let _xmlNamespace: String? = "https://test.amazonaws.com/doc/2020-03-11/"
            let number: Int
        }
        struct Input: AWSShape {
            public static let payloadPath: String? = "payload"
            let payload: Payload
        }

        do {
            let input = Input(payload: Payload(number: 5))
            let request = try s3Client.createAWSRequest(operation: "Test", path: "/", httpMethod: "GET", input: input)
            if case .xml(let element) = request.body {
                XCTAssertEqual(element.xmlString, "<Payload xmlns=\"https://test.amazonaws.com/doc/2020-03-11/\"><number>5</number></Payload>")
            } else {
                XCTFail("Shouldn't get here")
            }
        } catch {
            XCTFail("\(error)")
        }
    }

    func testValidateCode() {
        let response = AWSHTTPResponseImpl(
            status: .ok,
            headers: HTTPHeaders(),
            body: nil
        )
        do {
            try s3Client.validate(response: response)
        } catch {
            XCTFail(error.localizedDescription)
        }

        let failResponse = AWSHTTPResponseImpl(
            status: .forbidden,
            headers: HTTPHeaders(),
            body: nil
        )

        do {
            try s3Client.validate(response: failResponse)
            XCTFail("call to validateCode should throw an error")
        } catch {
            XCTAssertTrue(true)
        }
    }

    func testValidateXMLResponse() {
        class Output : AWSShape {
            let name : String
        }
        let responseBody = "<Output><name>hello</name></Output>"
        let awsHTTPResponse = AWSHTTPResponseImpl(
            status: .ok,
            headers: HTTPHeaders(),
            bodyData: responseBody.data(using: .utf8)!
        )
        do {
            let output : Output = try s3Client.validate(operation: "Output", response: awsHTTPResponse)
            XCTAssertEqual(output.name, "hello")
        } catch {
            XCTFail(error.localizedDescription)
        }
    }

    func testValidateXMLCodablePayloadResponse() {
        class Output : AWSShape {
            static let _encoding = [AWSMemberEncoding(label: "contentType", location: .header(locationName: "content-type"))]
            static let payloadPath: String? = "name"
            let name : String
            let contentType: String

            private enum CodingKeys: String, CodingKey {
                case name = "name"
                case contentType = "content-type"
            }
        }
        let response = AWSHTTPResponseImpl(
            status: .ok,
            headers: ["Content-Type":"application/json"],
            bodyData: "<name>hello</name>".data(using: .utf8)!
        )
        do {
            let output : Output = try s3Client.validate(operation: "Output", response: response)
            XCTAssertEqual(output.name, "hello")
            XCTAssertEqual(output.contentType, "application/json")
        } catch {
            XCTFail(error.localizedDescription)
        }
    }

    func testValidateXMLRawPayloadResponse() {
        class Output : AWSShape {
            static let payloadPath: String? = "body"
            public static var _encoding = [
                AWSMemberEncoding(label: "body", encoding: .blob)
            ]
            let body : Data
        }
        let response = AWSHTTPResponseImpl(
            status: .ok,
            headers: HTTPHeaders(),
            bodyData: "{\"name\":\"hello\"}".data(using: .utf8)!
        )
        do {
            let output : Output = try s3Client.validate(operation: "Output", response: response)
            XCTAssertEqual(output.body, "{\"name\":\"hello\"}".data(using: .utf8))
        } catch {
            XCTFail(error.localizedDescription)
        }
    }

    func testValidateXMLError() {
        let response = AWSHTTPResponseImpl(
            status: .notFound,
            headers: HTTPHeaders(),
            bodyData: "<Error><Code>NoSuchKey</Code><Message>It doesn't exist</Message></Error>".data(using: .utf8)!
        )
        do {
            try s3Client.validate(response: response)
            XCTFail("Should not get here")
        } catch S3ErrorType.noSuchKey(let message) {
            XCTAssertEqual(message, "It doesn't exist")
        } catch {
            XCTFail("Throwing the wrong error")
        }
    }

    func testValidateRawResponseError() {
        class Output : AWSShape {
            static let payloadPath: String? = "output"
            public static var _members = [AWSMemberEncoding(label: "output", encoding: .blob)]
            let output : Data
        }
        do {
            let response = AWSHTTPResponseImpl(
                status: .notFound,
                headers: HTTPHeaders(),
                bodyData: "<Error><Code>NoSuchKey</Code><Message>It doesn't exist</Message></Error>".data(using: .utf8)!
            )
            let _: Output = try s3Client.validate(operation: "TestOperation", response: response)
            XCTFail("Shouldn't get here")
        } catch S3ErrorType.noSuchKey(let message) {
            XCTAssertEqual(message, "It doesn't exist")
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testValidateQueryError() {
        let response = AWSHTTPResponseImpl(
            status: .notFound,
            headers: HTTPHeaders(),
            bodyData: "<ErrorResponse><Error><Code>MessageRejected</Code><Message>Don't like it</Message></Error></ErrorResponse>".data(using: .utf8)!
        )
        do {
            try sesClient.validate(response: response)
            XCTFail("Should not get here")
        } catch SESErrorType.messageRejected(let message) {
            XCTAssertEqual(message, "Don't like it")
        } catch {
            XCTFail("Throwing the wrong error")
        }
    }


    func testValidateJSONResponse() {
        class Output : AWSShape {
            let name : String
        }
        let response = AWSHTTPResponseImpl(
            status: .ok,
            headers: HTTPHeaders(),
            bodyData: "{\"name\":\"hello\"}".data(using: .utf8)!
        )
        do {
            let output : Output = try kinesisClient.validate(operation: "Output", response: response)
            XCTAssertEqual(output.name, "hello")
        } catch {
            XCTFail(error.localizedDescription)
        }
    }

    func testValidateJSONCodablePayloadResponse() {
        class Output2 : AWSShape {
            let name : String
        }
        class Output : AWSShape {
            static let payloadPath: String? = "output2"
            let output2 : Output2
        }
        let response = AWSHTTPResponseImpl(
            status: .ok,
            headers: HTTPHeaders(),
            bodyData: "{\"name\":\"hello\"}".data(using: .utf8)!
        )
        do {
            let output : Output = try kinesisClient.validate(operation: "Output", response: response)
            XCTAssertEqual(output.output2.name, "hello")
        } catch {
            XCTFail(error.localizedDescription)
        }
    }

    func testValidateJSONRawPayloadResponse() {
        struct Output : AWSShape {
            static let payloadPath: String? = "body"
            public static var _encoding = [
                AWSMemberEncoding(label: "contentType", location: .header(locationName: "content-type")),
                AWSMemberEncoding(label: "body", encoding: .blob)
            ]
            let body : Data
            let contentType: String

            private enum CodingKeys: String, CodingKey {
                case body = "body"
                case contentType = "content-type"
            }
        }
        let response = AWSHTTPResponseImpl(
            status: .ok,
            headers: ["Content-Type":"application/json"],
            bodyData: "{\"name\":\"hello\"}".data(using: .utf8)!
        )
        do {
            let output : Output = try kinesisClient.validate(operation: "Output", response: response)
            XCTAssertEqual(output.body, "{\"name\":\"hello\"}".data(using: .utf8))
            XCTAssertEqual(output.contentType, "application/json")
        } catch {
            XCTFail(error.localizedDescription)
        }
    }

    func testValidateJSONError() {
        let response = AWSHTTPResponseImpl(
            status: .notFound,
            headers: HTTPHeaders(),
            bodyData: "{\"__type\":\"ResourceNotFoundException\", \"message\": \"Donald Where's Your Troosers?\"}".data(using: .utf8)!
        )
        do {
            try kinesisClient.validate(response: response)
            XCTFail("Should not get here")
        } catch KinesisErrorType.resourceNotFoundException(let message) {
            XCTAssertEqual(message, "Donald Where's Your Troosers?")
        } catch {
            XCTFail("Throwing the wrong error")
        }
    }


    func testProcessHAL() {
        class Output : AWSShape {
            let s: String
            let i: Int
        }
        class Output2 : AWSShape {
            let a: [Output]
            let d: Double
            let b: Bool
        }
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
            let output : Output2 = try kinesisClient.validate(operation: "Output", response: response)
            XCTAssertEqual(output.a.count, 2)
            XCTAssertEqual(output.d, 3.14)
            XCTAssertEqual(output.a[1].s, "Hello2")
        } catch {
            XCTFail(error.localizedDescription)
        }
    }

    func testDataInJsonPayload() {
        struct DataContainer: AWSShape {
            let data: Data
        }
        struct J: AWSShape {
            public static let payloadPath: String? = "dataContainer"
            let dataContainer: DataContainer
        }
        let input = J(dataContainer: DataContainer(data: Data("test data".utf8)))
        do {
            _ = try kinesisClient.createAWSRequest(
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
        struct Response: AWSShape {
            public static let payloadPath: String? = "data"
            public static var _encoding = [
                AWSMemberEncoding(label: "data", encoding: .blob),
            ]
            let data: Data
        }
        var buffer = ByteBufferAllocator().buffer(capacity: 0)
        buffer.writeString("TestString")
        let response = HTTPClient.Response(
            host: "localhost",
            status: .ok,
            headers: ["Content-Type":"application/hal+json"],
            body: buffer
        )
        do {
            let output : Response = try kinesisClient.validate(operation: "Output", response: response)
            XCTAssertEqual(String(data: output.data, encoding: .utf8), "TestString")
        } catch {
            XCTFail(error.localizedDescription)
        }
    }

    func testClientNoInputNoOutput() {
        do {
            let awsServer = AWSTestServer(serviceProtocol: .json)
            let client = AWSClient(
                accessKeyId: "",
                secretAccessKey: "",
                region: .useast1,
                service:"TestClient",
                serviceProtocol: ServiceProtocol(type: .json, version: ServiceProtocol.Version(major: 1, minor: 1)),
                apiVersion: "2020-01-21",
                endpoint: awsServer.address,
                middlewares: [AWSLoggingMiddleware()],
                httpClientProvider: .createNew
            )
            let response = client.send(operation: "test", path: "/", httpMethod: "POST")

            try awsServer.process { request in
                let response = AWSTestServer.Response(httpStatus: .ok, headers: [:], body: nil)
                return AWSTestServer.Result(output: response, continueProcessing: false)
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
        struct Input : AWSShape {
            let e: InputEnum
            let i: [Int64]
        }

        do {
            let awsServer = AWSTestServer(serviceProtocol: .json)
            let client = AWSClient(
                accessKeyId: "",
                secretAccessKey: "",
                region: .useast1,
                service:"TestClient",
                serviceProtocol: ServiceProtocol(type: .json, version: ServiceProtocol.Version(major: 1, minor: 1)),
                apiVersion: "2020-01-21",
                endpoint: awsServer.address,
                middlewares: [AWSLoggingMiddleware()],
                httpClientProvider: .createNew
            )
            let input = Input(e:.second, i: [1,2,4,8])
            let response = client.send(operation: "test", path: "/", httpMethod: "POST", input: input)

            try awsServer.process { request in
                let receivedInput = try JSONDecoder().decode(Input.self, from: request.body)
                XCTAssertEqual(receivedInput.e, .second)
                XCTAssertEqual(receivedInput.i, [1,2,4,8])
                let response = AWSTestServer.Response(httpStatus: .ok, headers: [:], body: nil)
                return AWSTestServer.Result(output: response, continueProcessing: false)
            }

            try response.wait()
            try awsServer.stop()
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testClientNoInputWithOutput() {
        struct Output : AWSShape {
            let s: String
            let i: Int64
        }
        do {
            let awsServer = AWSTestServer(serviceProtocol: .json)
            let client = AWSClient(
                accessKeyId: "",
                secretAccessKey: "",
                region: .useast1,
                service:"TestClient",
                serviceProtocol: ServiceProtocol(type: .json, version: ServiceProtocol.Version(major: 1, minor: 1)),
                apiVersion: "2020-01-21",
                endpoint: awsServer.address,
                middlewares: [AWSLoggingMiddleware()],
                httpClientProvider: .createNew
            )
            let response: EventLoopFuture<Output> = client.send(operation: "test", path: "/", httpMethod: "POST")

            try awsServer.process { request in
                let output = Output(s: "TestOutputString", i: 547)
                let byteBuffer = try JSONEncoder().encodeAsByteBuffer(output, allocator: ByteBufferAllocator())
                let response = AWSTestServer.Response(httpStatus: .ok, headers: [:], body: byteBuffer)
                return AWSTestServer.Result(output: response, continueProcessing: false)
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
        struct Input: AWSShape {
            static let _encoding = [AWSMemberEncoding(label: "array", location: .body(locationName: "Array"), encoding: .list(member:"item"))]
            let array: [String]
        }
        do {
            let input = Input(array: ["entry1", "entry2"])
            let request = try ec2Client.createAWSRequest(operation: "Test", path: "/", httpMethod: "GET", input: input)
            XCTAssertEqual(request.body.asString(), "Action=Test&Version=2013-12-02&array.1=entry1&array.2=entry2")
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
        do {
            try ec2Client.validate(response: response)
            XCTFail("Should not get here")
        } catch let error as AWSResponseError {
            XCTAssertEqual(error.errorCode, "NoSuchKey")
            XCTAssertEqual(error.message, "It doesn't exist")
        } catch {
            XCTFail("Throwing the wrong error")
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
                try? httpClient.syncShutdown()
            }
            let client = AWSClient(
                accessKeyId: "",
                secretAccessKey: "",
                region: .useast1,
                service:"TestClient",
                serviceProtocol: ServiceProtocol(type: .json, version: ServiceProtocol.Version(major: 1, minor: 1)),
                apiVersion: "2020-01-21",
                endpoint: awsServer.address,
                middlewares: [AWSLoggingMiddleware()],
                httpClientProvider: .shared(httpClient)
            )
            let response = client.send(operation: "test", path: "/", httpMethod: "POST")

            try awsServer.process { request in
                let response = AWSTestServer.Response(httpStatus: .temporaryRedirect, headers: ["Location":awsServer.address], body: nil)
                return AWSTestServer.Result(output: response, continueProcessing: false)
            }

            try response.wait()
            try awsServer.stop()
            XCTFail("Shouldn't get here as the provided client doesn't follow redirects")
        } catch let error as AWSError {
            XCTAssertEqual(error.message, "Unhandled Error. Response Code: 307")
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }
}

/// Error enum for Kinesis
public enum KinesisErrorType: AWSErrorType {
    case resourceNotFoundException(message: String?)
}

extension KinesisErrorType {
    public init?(errorCode: String, message: String?){
        switch errorCode {
        case "ResourceNotFoundException":
            self = .resourceNotFoundException(message: message)
        default:
            return nil
        }
    }

    public var description : String {
        switch self {
        case .resourceNotFoundException(let message):
            return "ResourceNotFoundException :\(message ?? "")"
        }
    }
}

/// Error enum for S3
public enum S3ErrorType: AWSErrorType {
    case noSuchKey(message: String?)
}

extension S3ErrorType {
    public init?(errorCode: String, message: String?){
        switch errorCode {
        case "NoSuchKey":
            self = .noSuchKey(message: message)
        default:
            return nil
        }
    }

    public var description : String {
        switch self {
        case .noSuchKey(let message):
            return "NoSuchKey :\(message ?? "")"
        }
    }
}

/// Error enum for SES
public enum SESErrorType: AWSErrorType {
    case messageRejected(message: String?)
}

extension SESErrorType {
    public init?(errorCode: String, message: String?){
        switch errorCode {
        case "MessageRejected":
            self = .messageRejected(message: message)
        default:
            return nil
        }
    }

    public var description : String {
        switch self {
        case .messageRejected(let message):
            return "MessageRejected :\(message ?? "")"
        }
    }
}
