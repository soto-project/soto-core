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
            ("testUnsignedClient", testUnsignedClient),
            ("testProtocolContentType", testProtocolContentType),
            ("testHeaderEncoding", testHeaderEncoding),
            ("testQueryEncoding", testQueryEncoding),
            ("testQueryEncodedArray", testQueryEncodedArray),
            ("testQueryEncodedDictionary", testQueryEncodedDictionary),
            ("testURIEncoding", testURIEncoding),
            ("testValidateXMLResponse", testValidateXMLResponse),
            ("testValidateXMLCodablePayloadResponse", testValidateXMLCodablePayloadResponse),
            ("testXMLError", testXMLError),
            ("testValidateQueryError", testQueryError),
            ("testValidateJSONResponse", testValidateJSONResponse),
            ("testValidateJSONCodablePayloadResponse", testValidateJSONCodablePayloadResponse),
            ("testValidateJSONRawPayloadResponse", testValidateJSONRawPayloadResponse),
            ("testValidateJSONError", testJSONError),
            ("testProcessHAL", testProcessHAL),
            ("testDataInJsonPayload", testDataInJsonPayload),
            ("testPayloadDataInResponse", testPayloadDataInResponse),
            ("testClientNoInputNoOutput", testClientNoInputNoOutput),
            ("testClientWithInputNoOutput", testClientWithInputNoOutput),
            ("testClientNoInputWithOutput", testClientNoInputWithOutput),
            ("testEC2ClientRequest", testEC2ClientRequest),
            ("testEC2ValidateError", testEC2ValidateError),
            ("testRegionEnum", testRegionEnum),
            ("testServerError", testServerError),
            ("testClientRetry", testClientRetry),
            ("testClientRetryFail", testClientRetryFail),
            ("testClientResponseEventLoop", testClientResponseEventLoop),
        ]
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
        let sesClient = AWSClient(
            accessKeyId: "key",
            secretAccessKey: "secret",
            region: nil,
            service: "email",
            serviceProtocol: .query,
            apiVersion: "2013-12-01",
            middlewares: [],
            httpClientProvider: .createNew
        )

        do {
            let credentialForSignature = try sesClient.credentialProvider.getCredential(on: sesClient.eventLoopGroup.next()).wait()
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
            serviceProtocol: .query,
            apiVersion: "2013-12-01",
            httpClientProvider: .createNew)

        do {
            let credentials = try client.credentialProvider.getCredential(on: client.eventLoopGroup.next()).wait()
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
        serviceProtocol: .query,
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
        serviceProtocol: .json(version: "1.1"),
        apiVersion: "2013-12-02",
        middlewares: [AWSLoggingMiddleware()],
        possibleErrorTypes: [KinesisErrorType.self],
        httpClientProvider: .createNew
    )

    let s3Client = AWSClient(
        accessKeyId: "foo",
        secretAccessKey: "bar",
        region: .cacentral1,
        service: "s3",
        serviceProtocol: .restxml,
        apiVersion: "2006-03-01",
        endpoint: nil,
        serviceEndpoints: ["us-west-2": "s3.us-west-2.amazonaws.com", "eu-west-1": "s3.eu-west-1.amazonaws.com", "us-east-1": "s3.amazonaws.com", "ap-northeast-1": "s3.ap-northeast-1.amazonaws.com", "s3-external-1": "s3-external-1.amazonaws.com", "ap-southeast-2": "s3.ap-southeast-2.amazonaws.com", "sa-east-1": "s3.sa-east-1.amazonaws.com", "ap-southeast-1": "s3.ap-southeast-1.amazonaws.com", "us-west-1": "s3.us-west-1.amazonaws.com"],
        middlewares: [AWSLoggingMiddleware()],
        possibleErrorTypes: [S3ErrorType.self],
        httpClientProvider: .createNew
    )

    let ec2Client = AWSClient(
        accessKeyId: "foo",
        secretAccessKey: "bar",
        region: nil,
        service: "ec2",
        serviceProtocol: .ec2,
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
            XCTAssertEqual(awsRequest.url.absoluteString, "\(sesClient.serviceConfig.endpoint)/")
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
            serviceProtocol: .json(version: "1.1"),
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
            XCTAssertEqual(awsRequest.url.absoluteString, "\(kinesisClient.serviceConfig.endpoint)/")

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

            XCTAssertEqual(awsRequest.url.absoluteString, "https://s3.ca-central-1.amazonaws.com/Bucket?list-type=2")
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
        struct KeywordRequest: AWSEncodableShape {
            static var _encoding: [AWSMemberEncoding] = [
                AWSMemberEncoding(label: "self", location: .querystring(locationName: "self")),
            ]
            let `self`: String
        }
        do {
            let request = KeywordRequest(self: "KeywordRequest")
            let awsRequest = try s3Client.createAWSRequest(operation: "Keyword", path: "/", httpMethod: "POST", input: request)
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
            serviceProtocol: .restxml,
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
        do {
            let input = Input(h: "TestHeader")
            let request = try kinesisClient.createAWSRequest(operation: "Test", path: "/", httpMethod: "GET", input: input)
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
        do {
            let input = Input(q: "=3+5897^sdfjh&")
            let request = try kinesisClient.createAWSRequest(operation: "Test", path: "/", httpMethod: "GET", input: input)
            XCTAssertEqual(request.url.absoluteString, "https://kinesis.us-east-1.amazonaws.com/?query=%3D3%2B5897%5Esdfjh%26")
        } catch {
            XCTFail("\(error)")
        }
    }

    func testQueryEncodedArray() {
        struct Input: AWSEncodableShape {
            static let _encoding = [AWSMemberEncoding(label: "q", location: .querystring(locationName: "query"))]
            let q: [String]
        }
        do {
            let input = Input(q: ["=3+5897^sdfjh&", "test"])
            let request = try kinesisClient.createAWSRequest(operation: "Test", path: "/", httpMethod: "GET", input: input)
            XCTAssertEqual(request.url.absoluteString, "https://kinesis.us-east-1.amazonaws.com/?query=%3D3%2B5897%5Esdfjh%26&query=test")
        } catch {
            XCTFail("\(error)")
        }
    }

    func testQueryEncodedDictionary() {
        struct Input: AWSEncodableShape {
            static let _encoding = [AWSMemberEncoding(label: "q", location: .querystring(locationName: "query"))]
            let q: [String: Int]
        }
        do {
            let input = Input(q: ["one": 1, "two": 2])
            let request = try s3Client.createAWSRequest(operation: "Test", path: "/", httpMethod: "GET", input: input)
            XCTAssertEqual(request.url.absoluteString, "https://s3.ca-central-1.amazonaws.com/?one=1&two=2")
        } catch {
            XCTFail("\(error)")
        }
    }

    func testURIEncoding() {
        struct Input: AWSEncodableShape {
            static let _encoding = [AWSMemberEncoding(label: "u", location: .uri(locationName: "key"))]
            let u: String
        }
        do {
            let input = Input(u: "MyKey")
            let request = try s3Client.createAWSRequest(operation: "Test", path: "/{key}", httpMethod: "GET", input: input)
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
        do {
            let result: Output = try sesClient.validate(operation: "Test", response: response)
            XCTAssertEqual(result.h, "test-header")
        } catch {
            XCTFail("\(error)")
        }

        // JSON
        do {
            let result: Output = try kinesisClient.validate(operation: "Test", response: response)
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
        do {
            let result: Output = try s3Client.validate(operation: "Test", response: response)
            XCTAssertEqual(result.status, 200)
        } catch {
            XCTFail("\(error)")
        }
        // JSON
        do {
            let result: Output = try kinesisClient.validate(operation: "Test", response: response)
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
        struct Payload: AWSEncodableShape {
            public static let _xmlNamespace: String? = "https://test.amazonaws.com/doc/2020-03-11/"
            let number: Int
        }
        struct Input: AWSEncodableShape & AWSShapeWithPayload {
            public static let payloadPath: String = "payload"
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

    func testValidateXMLResponse() {
        class Output : AWSDecodableShape {
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
        class Output : AWSDecodableShape, AWSShapeWithPayload {
            static let payloadPath: String = "body"
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

    func testXMLError() {
        let response = AWSHTTPResponseImpl(
            status: .notFound,
            headers: HTTPHeaders(),
            bodyData: "<Error><Code>NoSuchKey</Code><Message>It doesn't exist</Message></Error>".data(using: .utf8)!
        )
        let error = s3Client.createError(for: response)
        if case S3ErrorType.noSuchKey(let message) = error {
            XCTAssertEqual(message, "It doesn't exist")
        } else {
            XCTFail("Error is not noSuchKey")
        }
    }

/*    func testValidateXMLRawPayloadResponse() {
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
      }*/

    func testQueryError() {
        let response = AWSHTTPResponseImpl(
            status: .notFound,
            headers: HTTPHeaders(),
            bodyData: "<ErrorResponse><Error><Code>MessageRejected</Code><Message>Don't like it</Message></Error></ErrorResponse>".data(using: .utf8)!
        )
        let error = sesClient.createError(for: response)
        if case SESErrorType.messageRejected(let message) = error {
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
        do {
            let output : Output = try kinesisClient.validate(operation: "Output", response: response)
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
        struct Output : AWSDecodableShape, AWSShapeWithPayload {
            static let payloadPath: String = "body"
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

    func testJSONError() {
        let response = AWSHTTPResponseImpl(
            status: .notFound,
            headers: HTTPHeaders(),
            bodyData: "{\"__type\":\"ResourceNotFoundException\", \"message\": \"Donald Where's Your Troosers?\"}".data(using: .utf8)!
        )
        let error = kinesisClient.createError(for: response)
        if case KinesisErrorType.resourceNotFoundException(let message) = error {
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
        struct DataContainer: AWSEncodableShape {
            let data: Data
        }
        struct J: AWSEncodableShape & AWSShapeWithPayload {
            public static let payloadPath: String = "dataContainer"
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
        struct Response: AWSDecodableShape & AWSShapeWithPayload {
            public static let payloadPath: String = "data"
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
                serviceProtocol: .json(version: "1.1"),
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
        struct Input : AWSEncodableShape & Decodable {
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
                serviceProtocol: .json(version: "1.1"),
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
        struct Output : AWSDecodableShape & Encodable {
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
                serviceProtocol: .json(version: "1.1"),
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
        struct Input: AWSEncodableShape {
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
        if let error = ec2Client.createError(for: response) as? AWSResponseError {
            XCTAssertEqual(error.errorCode, "NoSuchKey")
            XCTAssertEqual(error.message, "It doesn't exist")
        } else {
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
                XCTAssertNoThrow(try awsServer.stop())
                XCTAssertNoThrow(try httpClient.syncShutdown())
            }
            let client = AWSClient(
                accessKeyId: "",
                secretAccessKey: "",
                region: .useast1,
                service:"TestClient",
                serviceProtocol: .json(version: "1.1"),
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
            XCTFail("Shouldn't get here as the provided client doesn't follow redirects")
        } catch let error as AWSError {
            XCTAssertEqual(error.message, "Unhandled Error. Response Code: 307")
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testRegionEnum() {
        let regions = [
            "us-east-1",
            "us-east-2",
            "us-west-1",
            "us-west-2",
            "ap-south-1",
            "ap-northeast-2",
            "ap-southeast-1",
            "ap-southeast-2",
            "ap-northeast-1",
            "ap-east-1",
            "ca-central-1",
            "eu-west-1",
            "eu-west-3",
            "eu-west-2",
            "eu-central-1",
            "eu-north-1",
            "sa-east-1",
            "me-south-1"
        ]
        regions.forEach {
            let region = Region(rawValue: $0)
            if case .other(_) = region {
                XCTFail("\($0) is not a region")
            }
            let rawValue = region.rawValue
            XCTAssertEqual(rawValue, $0)
        }

        let region = Region(rawValue: "my-region")
        if case .other(let regionName) = region {
            XCTAssertEqual(regionName, "my-region")
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
            let client = AWSClient(
                accessKeyId: "",
                secretAccessKey: "",
                region: .useast1,
                service:"TestClient",
                serviceProtocol: .json(version: "1.1"),
                apiVersion: "2020-01-21",
                endpoint: awsServer.address,
                retryController: ExponentialRetry(base: .milliseconds(200)),
                middlewares: [AWSLoggingMiddleware()],
                httpClientProvider: .shared(httpClient)
            )
            let response = client.send(operation: "test", path: "/", httpMethod: "POST")

            try awsServer.processWithErrors(process: { request in
                let response = AWSTestServer.Response(httpStatus: .ok, headers: [:], body: nil)
                return AWSTestServer.Result(output: response, continueProcessing: false)
            }, errors: { count in
                if count < 5 {
                    return AWSTestServer.Result(output: AWSTestServer.ErrorType.internal, continueProcessing: true)
                } else {
                    return AWSTestServer.Result(output: nil, continueProcessing: false)
                }
            })

            try response.wait()
        } catch AWSServerError.internalError(let message) {
            XCTAssertEqual(message, AWSTestServer.ErrorType.internal.message)
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
            let client = AWSClient(
                accessKeyId: "",
                secretAccessKey: "",
                region: .useast1,
                service:"TestClient",
                serviceProtocol: .json(version: "1.1"),
                apiVersion: "2020-01-21",
                endpoint: awsServer.address,
                retryController: JitterRetry(),
                middlewares: [AWSLoggingMiddleware()],
                httpClientProvider: .shared(httpClient)
            )
            let response: EventLoopFuture<Output> = client.send(operation: "test", path: "/", httpMethod: "POST")

            try awsServer.processWithErrors(process: { request in
                let output = Output(s: "TestOutputString")
                let byteBuffer = try JSONEncoder().encodeAsByteBuffer(output, allocator: ByteBufferAllocator())
                let response = AWSTestServer.Response(httpStatus: .ok, headers: [:], body: byteBuffer)
                return AWSTestServer.Result(output: response, continueProcessing: false)
            }, errors: { count in
                if count < 3 {
                    return AWSTestServer.Result(output: AWSTestServer.ErrorType.notImplemented, continueProcessing: true)
                } else {
                    return AWSTestServer.Result(output: nil, continueProcessing: true)
                }
            })

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
            let client = AWSClient(
                accessKeyId: "",
                secretAccessKey: "",
                region: .useast1,
                service:"TestClient",
                serviceProtocol: .json(version: "1.1"),
                apiVersion: "2020-01-21",
                endpoint: awsServer.address,
                retryController: JitterRetry(),
                middlewares: [AWSLoggingMiddleware()],
                httpClientProvider: .shared(httpClient)
            )
            let response: EventLoopFuture<Output> = client.send(operation: "test", path: "/", httpMethod: "POST")

            try awsServer.processWithErrors(process: { request in
                let output = Output(s: "TestOutputString")
                let byteBuffer = try JSONEncoder().encodeAsByteBuffer(output, allocator: ByteBufferAllocator())
                let response = AWSTestServer.Response(httpStatus: .ok, headers: [:], body: byteBuffer)
                return AWSTestServer.Result(output: response, continueProcessing: false)
            }, errors: { count in
                return AWSTestServer.Result(output: AWSTestServer.ErrorType.accessDenied, continueProcessing: false)
            })

            let output = try response.wait()

            XCTAssertEqual(output.s, "TestOutputString")
        } catch AWSClientError.accessDenied(let message) {
            XCTAssertEqual(message, AWSTestServer.ErrorType.accessDenied.message)
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
            let client = AWSClient(
                accessKeyId: "",
                secretAccessKey: "",
                region: .useast1,
                service:"TestClient",
                serviceProtocol: .json(version: "1.1"),
                apiVersion: "2020-01-21",
                endpoint: awsServer.address,
                httpClientProvider: .shared(httpClient)
            )
            let eventLoop = client.eventLoopGroup.next()
            let response: EventLoopFuture<Void> = client.send(operation: "test", path: "/", httpMethod: "POST", on: eventLoop)

            try awsServer.process { request in
                return AWSTestServer.Result(output: .ok, continueProcessing: false)
            }
            XCTAssertTrue(eventLoop === response.eventLoop)

            try response.wait()
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
