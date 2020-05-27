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

        var credentialForSignature: Credential?
        XCTAssertNoThrow(credentialForSignature = try client.credentialProvider.getCredential(on: client.eventLoopGroup.next()).wait())
        XCTAssertEqual(credentialForSignature?.accessKeyId, "key")
        XCTAssertEqual(credentialForSignature?.secretAccessKey, "secret")
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
        let config = createServiceConfig(
            serviceEndpoints: ["aws-global":"service.aws.amazon.com"],
            partitionEndpoints: [.aws: (endpoint: "aws-global", region: .euwest1)]
        )
        // XCTAssertEqual(client.region, .euwest1) // FIXME: How has this ever worked?
        XCTAssertEqual(config.region, .euwest1)
        
        let awsRequest = try AWSRequest(operation: "test", path: "/", httpMethod: "GET", configuration: config)
        XCTAssertEqual(awsRequest.url.absoluteString, "https://service.aws.amazon.com/")
    }

    
    func testCreateAwsRequestWithKeywordInHeader() {
        struct KeywordRequest: AWSEncodableShape {
            static var _encoding: [AWSMemberEncoding] = [
                AWSMemberEncoding(label: "repeat", location: .header(locationName: "repeat")),
            ]
            let `repeat`: String
        }
        let config = createServiceConfig()
        
        let input = KeywordRequest(repeat: "Repeat")
        var request: AWSRequest?
        XCTAssertNoThrow(request = try AWSRequest(operation: "Keyword", path: "/", httpMethod: "POST", input: input, configuration: config))
        XCTAssertEqual(request?.httpHeaders["repeat"] as? String, "Repeat")
        XCTAssertTrue(try XCTUnwrap(request).body.asPayload().isEmpty)
    }

    func testCreateAwsRequestWithKeywordInQuery() {
        struct KeywordRequest: AWSEncodableShape {
            static var _encoding: [AWSMemberEncoding] = [
                AWSMemberEncoding(label: "self", location: .querystring(locationName: "self")),
            ]
            let `self`: String
        }
        let config = createServiceConfig(region: .cacentral1, service: "s3")
        
        let input = KeywordRequest(self: "KeywordRequest")
        var request: AWSRequest?
        XCTAssertNoThrow(request = try AWSRequest(operation: "Keyword", path: "/", httpMethod: "POST", input: input, configuration: config))
        XCTAssertEqual(request?.url, URL(string:"https://s3.ca-central-1.amazonaws.com/?self=KeywordRequest")!)
        XCTAssertTrue(try XCTUnwrap(request).body.asPayload().isEmpty)
    }

    func testCreateNIORequest() {
        let input2 = E()
        
        let config = createServiceConfig(
            amzTarget: "Kinesis_20131202",
            service: "kinesis",
            serviceProtocol: .json(version: "1.1"),
            apiVersion: "2013-12-02",
            possibleErrorTypes: [ServiceErrorType.self])
        
        let signer = AWSSigner(
            credentials: StaticCredential(accessKeyId: "foo", secretAccessKey: "bar"),
            name: config.service,
            region: config.region.rawValue)
        var request: AWSRequest?
        XCTAssertNoThrow(request = try AWSRequest(operation: "PutRecord", path: "/", httpMethod: "POST", input: input2, configuration: config))
        var signedRequest: AWSHTTPRequest?
        XCTAssertNoThrow(signedRequest = request?.createHTTPRequest(signer: signer))
        
        XCTAssertEqual(signedRequest?.method, HTTPMethod.POST)
        XCTAssertEqual(signedRequest?.headers["Host"].first, "kinesis.us-east-1.amazonaws.com")
        XCTAssertEqual(signedRequest?.headers["Content-Type"].first, "application/x-amz-json-1.1")
        XCTAssertEqual(signedRequest?.headers["x-amz-target"].first, "Kinesis_20131202.PutRecord")
    }

    func testUnsignedClient() {
        let input = E()
        let config = createServiceConfig()
        var request: AWSRequest?
        XCTAssertNoThrow(request = try AWSRequest(
            operation: "CopyObject",
            path: "/",
            httpMethod: "PUT",
            input: input,
            configuration: config
        ))
        
        let signer = AWSSigner(
            credentials: StaticCredential(accessKeyId: "", secretAccessKey: ""),
            name: config.service,
            region: config.region.rawValue)

        var unsignedRequest: AWSHTTPRequest?
        XCTAssertNoThrow(unsignedRequest = request?.createHTTPRequest(signer: signer))
        XCTAssertNil(unsignedRequest?.headers["Authorization"].first)
    }
    
    func testSignedClient() {
        let input = E()
        let config = createServiceConfig()
        let signer = AWSSigner(
            credentials: StaticCredential(accessKeyId: "foo", secretAccessKey: "bar"),
            name: config.service,
            region: config.region.rawValue)
        
        for httpMethod in ["GET","HEAD","PUT","DELETE","POST","PATCH"] {
            var request: AWSRequest?
            
            XCTAssertNoThrow(request = try AWSRequest(
                operation: "Test",
                path: "/",
                httpMethod: httpMethod,
                input: input,
                configuration: config
            ))
            
            var signedRequest: AWSHTTPRequest?
            XCTAssertNoThrow(signedRequest = request?.createHTTPRequest(signer: signer))
            XCTAssertNotNil(signedRequest?.headers["Authorization"].first)
        }
    }

    func testProtocolContentType() {
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

        let config1 = createServiceConfig(serviceProtocol: .json(version: "1.1"))
        var request: AWSRequest?
        XCTAssertNoThrow(request = try AWSRequest(operation: "test", path: "/", httpMethod: "POST", input: object, configuration: config1))
        XCTAssertEqual(request?.getHttpHeaders()["content-type"].first, "application/x-amz-json-1.1")

        let config2 = createServiceConfig(serviceProtocol: .restjson)
        var request2: AWSRequest?
        XCTAssertNoThrow(request2 = try AWSRequest(operation: "test", path: "/", httpMethod: "POST", input: object, configuration: config2))
        XCTAssertEqual(request2?.getHttpHeaders()["content-type"].first, "application/json")
        var rawRequest2: AWSRequest?
        XCTAssertNoThrow(rawRequest2 = try AWSRequest(operation: "test", path: "/", httpMethod: "POST", input: object2, configuration: config2))
        XCTAssertEqual(rawRequest2?.getHttpHeaders()["content-type"].first, "binary/octet-stream")

        let config3 = createServiceConfig(serviceProtocol: .query)
        var request3: AWSRequest?
        XCTAssertNoThrow(request3 = try AWSRequest(operation: "test", path: "/", httpMethod: "POST", input: object, configuration: config3))
        XCTAssertEqual(request3?.getHttpHeaders()["content-type"].first, "application/x-www-form-urlencoded; charset=utf-8")

        let config4 = createServiceConfig(serviceProtocol: .ec2)
        var request4: AWSRequest?
        XCTAssertNoThrow(request4 = try AWSRequest(operation: "test", path: "/", httpMethod: "POST", input: object, configuration: config4))
        XCTAssertEqual(request4?.getHttpHeaders()["content-type"].first, "application/x-www-form-urlencoded; charset=utf-8")

        let config5 = createServiceConfig(serviceProtocol: .restxml)
        var request5: AWSRequest?
        XCTAssertNoThrow(request5 = try AWSRequest(operation: "test", path: "/", httpMethod: "POST", input: object, configuration: config5))
        XCTAssertEqual(request5?.getHttpHeaders()["content-type"].first, "application/octet-stream")
    }

    func testHeaderEncoding() {
        struct Input: AWSEncodableShape {
            static let _encoding = [AWSMemberEncoding(label: "h", location: .header(locationName: "header-member"))]
            let h: String
        }
        
        let config = createServiceConfig()
        let input = Input(h: "TestHeader")
        
        var request: AWSRequest?
        XCTAssertNoThrow(request = try AWSRequest(operation: "Test", path: "/", httpMethod: "GET", input: input, configuration: config))
        XCTAssertEqual(request?.httpHeaders["header-member"] as? String, "TestHeader")
    }

    func testQueryEncoding() {
        struct Input: AWSEncodableShape {
            static let _encoding = [AWSMemberEncoding(label: "q", location: .querystring(locationName: "query"))]
            let q: String
        }
        
        let config = createServiceConfig(service: "testService")
        let input = Input(q: "=3+5897^sdfjh&")
        var request: AWSRequest?
        XCTAssertNoThrow(request = try AWSRequest(operation: "Test", path: "/", httpMethod: "GET", input: input, configuration: config))
        XCTAssertEqual(request?.url.absoluteString, "https://testService.us-east-1.amazonaws.com/?query=%3D3%2B5897%5Esdfjh%26")
    }

    func testQueryEncodedArray() {
        struct Input: AWSEncodableShape {
            static let _encoding = [AWSMemberEncoding(label: "q", location: .querystring(locationName: "query"))]
            let q: [String]
        }
        let config = createServiceConfig(service: "testService")
        let input = Input(q: ["=3+5897^sdfjh&", "test"])
        var request: AWSRequest?
        XCTAssertNoThrow(request = try AWSRequest(operation: "Test", path: "/", httpMethod: "GET", input: input, configuration: config))
        XCTAssertEqual(request?.url.absoluteString, "https://testService.us-east-1.amazonaws.com/?query=%3D3%2B5897%5Esdfjh%26&query=test")
    }

    func testQueryEncodedDictionary() {
        struct Input: AWSEncodableShape {
            static let _encoding = [AWSMemberEncoding(label: "q", location: .querystring(locationName: "query"))]
            let q: [String: Int]
        }
        let config = createServiceConfig(region: .useast2, service: "myservice")
        let input = Input(q: ["one": 1, "two": 2])
        var request: AWSRequest?
        XCTAssertNoThrow(request = try AWSRequest(operation: "Test", path: "/", httpMethod: "GET", input: input, configuration: config))
        XCTAssertEqual(request?.url.absoluteString, "https://myservice.us-east-2.amazonaws.com/?one=1&two=2")
    }

    func testURIEncoding() {
        struct Input: AWSEncodableShape {
            static let _encoding = [AWSMemberEncoding(label: "u", location: .uri(locationName: "key"))]
            let u: String
        }
        let config = createServiceConfig(region: .cacentral1, service: "s3")
        let input = Input(u: "MyKey")
        var request: AWSRequest?
        XCTAssertNoThrow(request = try AWSRequest(operation: "Test", path: "/{key}", httpMethod: "GET", input: input, configuration: config))
        XCTAssertEqual(request?.url.absoluteString, "https://s3.ca-central-1.amazonaws.com/MyKey")
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
            bodyData: nil)

        // XML
        let queryConfig = createServiceConfig(serviceProtocol: .query)
        var queryResult: Output?
        XCTAssertNoThrow(queryResult = try response.validate(operation: "Test", configuration: queryConfig))
        XCTAssertEqual(queryResult?.h, "test-header")

        // JSON
        let jsonConfig = createServiceConfig(serviceProtocol: .restjson)
        var jsonResult: Output?
        XCTAssertNoThrow(jsonResult = try response.validate(operation: "Test", configuration: jsonConfig))
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
            bodyData: nil)

        // XML
        let xmlConfig = createServiceConfig(serviceProtocol: .restxml)
        var xmlResult: Output?
        XCTAssertNoThrow(xmlResult = try response.validate(operation: "Test", configuration: xmlConfig))
        XCTAssertEqual(xmlResult?.status, 200)
        
        // JSON
        let jsonConfig = createServiceConfig(serviceProtocol: .restjson)
        var jsonResult: Output?
        XCTAssertNoThrow(jsonResult = try response.validate(operation: "Test", configuration: jsonConfig))
        XCTAssertEqual(jsonResult?.status, 200)
    }

    func testCreateWithXMLNamespace() {
        struct Input: AWSEncodableShape {
            public static let _xmlNamespace: String? = "https://test.amazonaws.com/doc/2020-03-11/"
            let number: Int
        }
        let xmlConfig = createServiceConfig(serviceProtocol: .restxml)
        let input = Input(number: 5)
        var request: AWSRequest?
        XCTAssertNoThrow(request = try AWSRequest(operation: "Test", path: "/", httpMethod: "GET", input: input, configuration: xmlConfig))
        guard case .xml(let element) = request?.body else {
            return XCTFail("Expected to have an xml node")
        }
        XCTAssertEqual(element.xmlString, "<Input xmlns=\"https://test.amazonaws.com/doc/2020-03-11/\"><number>5</number></Input>")
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
        let xmlConfig = createServiceConfig(serviceProtocol: .restxml)
        let input = Input(payload: Payload(number: 5))
        var request: AWSRequest?
        XCTAssertNoThrow(request = try AWSRequest(operation: "Test", path: "/", httpMethod: "GET", input: input, configuration: xmlConfig))
        guard case .xml(let element) = request?.body else {
            return XCTFail("Expected to have an xml node")
        }
        XCTAssertEqual(element.xmlString, "<Payload xmlns=\"https://test.amazonaws.com/doc/2020-03-11/\"><number>5</number></Payload>")
    }

    func testValidateXMLResponse() {
        class Output : AWSDecodableShape {
            let name : String
        }
        let xmlConfig = createServiceConfig(serviceProtocol: .restxml)
        let responseBody = "<Output><name>hello</name></Output>"
        let awsHTTPResponse = AWSHTTPResponseImpl(
            status: .ok,
            headers: HTTPHeaders(),
            bodyData: responseBody.data(using: .utf8)!)
        
        var output: Output?
        XCTAssertNoThrow(output = try awsHTTPResponse.validate(operation: "Output", configuration: xmlConfig))
        XCTAssertEqual(output?.name, "hello")
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
        let xmlConfig = createServiceConfig(serviceProtocol: .restxml)
        let response = AWSHTTPResponseImpl(
            status: .ok,
            headers: ["Content-Type":"application/json"],
            bodyData: "<name>hello</name>".data(using: .utf8)!)
        
        var output: Output?
        XCTAssertNoThrow(output = try response.validate(operation: "Output", configuration: xmlConfig))
        XCTAssertEqual(output?.name, "hello")
        XCTAssertEqual(output?.contentType, "application/json")
    }

    func testValidateXMLRawPayloadResponse() {
        class Output : AWSDecodableShape, AWSShapeWithPayload {
            static let payloadPath: String = "body"
            public static var _encoding = [
                AWSMemberEncoding(label: "body", encoding: .blob)
            ]
            let body : AWSPayload
        }
        let xmlConfig = createServiceConfig(serviceProtocol: .restxml)
        let response = AWSHTTPResponseImpl(
            status: .ok,
            headers: HTTPHeaders(),
            bodyData: "{\"name\":\"hello\"}".data(using: .utf8)!)
        
        var output: Output?
        XCTAssertNoThrow(output = try response.validate(operation: "Output", configuration: xmlConfig))
        XCTAssertEqual(output?.body.asData(), "{\"name\":\"hello\"}".data(using: .utf8))
    }

    func testXMLError() {
        let response = AWSHTTPResponseImpl(
            status: .notFound,
            headers: HTTPHeaders(),
            bodyData: "<Error><Code>NoSuchKey</Code><Message>It doesn't exist</Message></Error>".data(using: .utf8)!
        )
        let xmlConfig = createServiceConfig(serviceProtocol: .restxml, possibleErrorTypes: [ServiceErrorType.self])
        let error = AWSClient.createError(for: response, configuration: xmlConfig)
        XCTAssertEqual(error as? ServiceErrorType, .noSuchKey(message: "It doesn't exist"))
    }

    func testQueryError() {
        let response = AWSHTTPResponseImpl(
            status: .notFound,
            headers: HTTPHeaders(),
            bodyData: "<ErrorResponse><Error><Code>MessageRejected</Code><Message>Don't like it</Message></Error></ErrorResponse>".data(using: .utf8)!
        )
        let queryConfig = createServiceConfig(serviceProtocol: .query, possibleErrorTypes: [ServiceErrorType.self])
        let error = AWSClient.createError(for: response, configuration: queryConfig)
        XCTAssertEqual(error as? ServiceErrorType, .messageRejected(message: "Don't like it"))
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
        let jsonConfig = createServiceConfig(serviceProtocol: .json(version: "1.1"))
        var output: Output?
        XCTAssertNoThrow(output = try response.validate(operation: "Output", configuration: jsonConfig))
        XCTAssertEqual(output?.name, "hello")
    }

    func testValidateJSONCodablePayloadResponse() {
        class Inner : AWSDecodableShape {
            let name : String
        }
        struct Outer : AWSDecodableShape & AWSShapeWithPayload {
            static let payloadPath: String = "output2"
            let output2 : Inner
        }
        let jsonConfig = createServiceConfig(serviceProtocol: .json(version: "1.1"))
        let response = AWSHTTPResponseImpl(
            status: .ok,
            headers: HTTPHeaders(),
            bodyData: "{\"name\":\"hello\"}".data(using: .utf8)!
        )
        var output: Outer?
        XCTAssertNoThrow(output = try response.validate(operation: "Output", configuration: jsonConfig))
        XCTAssertEqual(output?.output2.name, "hello")
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
        let jsonConfig = createServiceConfig(serviceProtocol: .json(version: "1.1"))
        let response = AWSHTTPResponseImpl(
            status: .ok,
            headers: ["Content-Type":"application/json"],
            bodyData: "{\"name\":\"hello\"}".data(using: .utf8)!
        )
        var output: Output?
        XCTAssertNoThrow(output = try response.validate(operation: "Output", configuration: jsonConfig))
        XCTAssertEqual(output?.body.asData(), "{\"name\":\"hello\"}".data(using: .utf8))
    }

    func testJSONError() {
        let response = AWSHTTPResponseImpl(
            status: .notFound,
            headers: HTTPHeaders(),
            bodyData: "{\"__type\":\"ResourceNotFoundException\", \"message\": \"Donald Where's Your Troosers?\"}".data(using: .utf8)!
        )
        let jsonConfig = createServiceConfig(serviceProtocol: .json(version: "1.1"), possibleErrorTypes: [ServiceErrorType.self])
        let error = AWSClient.createError(for: response, configuration: jsonConfig)
        XCTAssertEqual(error as? ServiceErrorType, .resourceNotFoundException(message: "Donald Where's Your Troosers?"))
    }

    func testProcessHAL() {
        struct Inner : AWSDecodableShape {
            let s: String
            let i: Int
        }
        struct Outer : AWSDecodableShape {
            let a: [Inner]
            let d: Double
            let b: Bool
        }
        let jsonConfig = createServiceConfig(serviceProtocol: .json(version: "1.1"))
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
        
        var output: Outer?
        XCTAssertNoThrow(output = try response.validate(operation: "Output", configuration: jsonConfig))
        XCTAssertEqual(output?.a.count, 2)
        XCTAssertEqual(output?.d, 3.14)
        XCTAssertEqual(output?.a[1].s, "Hello2")
    }

    func testDataInJsonPayload() {
        struct DataContainer: AWSEncodableShape {
            let data: Data
        }
        struct J: AWSEncodableShape & AWSShapeWithPayload {
            public static let payloadPath: String = "dataContainer"
            let dataContainer: DataContainer
        }
        let jsonConfig = createServiceConfig(serviceProtocol: .json(version: "1.1"))
        let input = J(dataContainer: DataContainer(data: Data("test data".utf8)))
        
        XCTAssertNoThrow(_ = try AWSRequest(operation: "PutRecord", path: "/", httpMethod: "POST", input: input, configuration: jsonConfig))
    }

    func testPayloadDataInResponse() {
        struct Output: AWSDecodableShape, AWSShapeWithPayload {
            public static let payloadPath: String = "payload"
            public static var _encoding = [
                AWSMemberEncoding(label: "payload", encoding: .blob),
            ]
            let payload: AWSPayload
        }
        let jsonConfig = createServiceConfig(serviceProtocol: .json(version: "1.1"))
        var buffer = ByteBufferAllocator().buffer(capacity: 0)
        buffer.writeString("TestString")
        let response = HTTPClient.Response(
            host: "localhost",
            status: .ok,
            headers: ["Content-Type":"application/hal+json"],
            body: buffer
        )
        var output: Output?
        XCTAssertNoThrow(output = try response.validate(operation: "Output", configuration: jsonConfig))
        XCTAssertEqual(output?.payload.asString(), "TestString")
    }

    func testClientNoInputNoOutput() {
        let awsServer = AWSTestServer(serviceProtocol: .json)
        let config = createServiceConfig(serviceProtocol: .json(version: "1.1"), endpoint: awsServer.address)
        let client = AWSClient(credentialProvider: nil, serviceConfig: config, httpClientProvider: .createNew)
        let response = client.execute(operation: "test", path: "/", httpMethod: "POST", with: config)

        XCTAssertNoThrow(try awsServer.processRaw { request in
            XCTAssertEqual(request.method, .POST)
            let response = AWSTestServer.Response(httpStatus: .ok, headers: [:], body: nil)
            return .result(response)
        })

        XCTAssertNoThrow(try response.wait())
        XCTAssertNoThrow(try awsServer.stop())
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

        let awsServer = AWSTestServer(serviceProtocol: .json)
        let config = createServiceConfig(serviceProtocol: .json(version: "1.1"), endpoint: awsServer.address)
        let client = AWSClient(credentialProvider: nil, serviceConfig: config, httpClientProvider: .createNew)
        
        let input = Input(e:.second, i: [1,2,4,8])
        let response = client.execute(operation: "test", path: "/", httpMethod: "POST", input: input, with: config)

        XCTAssertNoThrow(try awsServer.processRaw { request in
            let receivedInput = try JSONDecoder().decode(Input.self, from: request.body)
            XCTAssertEqual(receivedInput.e, .second)
            XCTAssertEqual(receivedInput.i, [1,2,4,8])
            let response = AWSTestServer.Response(httpStatus: .ok, headers: [:], body: nil)
            return .result(response)
        })

        XCTAssertNoThrow(try response.wait())
        XCTAssertNoThrow(try awsServer.stop())
    }

    func testClientNoInputWithOutput() {
        struct Output : AWSDecodableShape & Encodable {
            let s: String
            let i: Int64
        }

        let awsServer = AWSTestServer(serviceProtocol: .json)
        let config = createServiceConfig(serviceProtocol: .json(version: "1.1"), endpoint: awsServer.address)
        let client = AWSClient(credentialProvider: nil, serviceConfig: config, httpClientProvider: .createNew)
        let response: EventLoopFuture<Output> = client.execute(operation: "test", path: "/", httpMethod: "POST", with: config)

        XCTAssertNoThrow(try awsServer.processRaw { request in
            let output = Output(s: "TestOutputString", i: 547)
            let byteBuffer = try JSONEncoder().encodeAsByteBuffer(output, allocator: ByteBufferAllocator())
            let response = AWSTestServer.Response(httpStatus: .ok, headers: [:], body: byteBuffer)
            return .result(response)
        })

        var output: Output?
        XCTAssertNoThrow(output = try response.wait())
        XCTAssertEqual(output?.s, "TestOutputString")
        XCTAssertEqual(output?.i, 547)
        XCTAssertNoThrow(try awsServer.stop())
    }

    func testEC2ClientRequest() {
        struct Input: AWSEncodableShape {
            let array: [String]
        }
        let config = createServiceConfig(serviceProtocol: .ec2, apiVersion: "2013-12-02")
        let input = Input(array: ["entry1", "entry2"])
        var request: AWSRequest?
        XCTAssertNoThrow(request = try AWSRequest(operation: "Test", path: "/", httpMethod: "GET", input: input, configuration: config))
        XCTAssertEqual(request?.body.asString(), "Action=Test&Array.1=entry1&Array.2=entry2&Version=2013-12-02")
    }

    func testEC2ValidateError() {
        let response = AWSHTTPResponseImpl(
            status: .notFound,
            headers: HTTPHeaders(),
            bodyData: "<Errors><Error><Code>NoSuchKey</Code><Message>It doesn't exist</Message></Error></Errors>".data(using: .utf8)!
        )
        let config = createServiceConfig(serviceProtocol: .ec2)
        let error = AWSClient.createError(for: response, configuration: config) as? AWSResponseError
        XCTAssertEqual(error?.errorCode, "NoSuchKey")
        XCTAssertEqual(error?.message, "It doesn't exist")
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
        
        let config = createServiceConfig(serviceProtocol: .json(version: "1.1"), endpoint: awsServer.address)
        let client = AWSClient(credentialProvider: nil, serviceConfig: config, httpClientProvider: .shared(httpClient))
    
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
        let response = client.execute(operation: "test", path: "/", httpMethod: "POST", input: input, with: config)

        XCTAssertNoThrow(try awsServer.processRaw { request in
            let bytes = request.body.getBytes(at: 0, length: request.body.readableBytes)
            XCTAssertEqual(bytes, data)
            let response = AWSTestServer.Response(httpStatus: .ok, headers: [:], body: nil)
            return .result(response)
        })

        XCTAssertNoThrow(try response.wait())
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
            // We expect an `NonEmptyInboundBufferOnStop` to be thrown, since we kill the request
            // locally
            XCTAssertThrowsError(try awsServer.stop())
            XCTAssertNoThrow(try httpClient.syncShutdown())
        }
        
        let config = createServiceConfig(endpoint: awsServer.address)
        let client = AWSClient(credentialProvider: nil, serviceConfig: config, httpClientProvider: .shared(httpClient))
        
        let payload = AWSPayload.stream(size: 8) { eventLoop in
            var buffer = ByteBufferAllocator().buffer(capacity: 0)
            buffer.writeString("String longer than 8 bytes")
            return eventLoop.makeSucceededFuture(buffer)
        }
        let input = Input(payload: payload)
        let response = client.execute(operation: "test", path: "/", httpMethod: "POST", input: input, with: config)
        XCTAssertThrowsError(try response.wait()) { (error) in
            XCTAssertEqual(error as? AWSClient.ClientError, .tooMuchData)
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
            XCTAssertNoThrow(try awsServer.stop())
            XCTAssertNoThrow(try httpClient.syncShutdown())
        }

        let config = createServiceConfig(endpoint: awsServer.address)
        let client = AWSClient(credentialProvider: nil, serviceConfig: config, httpClientProvider: .shared(httpClient))

        let bufferSize = 208*1024
        let data = Data(createRandomBuffer(45,9182, size: bufferSize))
        let filename = "testRequestStreamingFile"
        let fileURL = URL(fileURLWithPath: filename)
        XCTAssertNoThrow(try data.write(to: fileURL))
        defer {
            XCTAssertNoThrow(try FileManager.default.removeItem(at: fileURL))
        }

        let threadPool = NIOThreadPool(numberOfThreads: 3)
        threadPool.start()
        let fileIO = NonBlockingFileIO(threadPool: threadPool)
        var fileHandle: NIOFileHandle?
        XCTAssertNoThrow(fileHandle = try fileIO.openFile(path: filename, mode: .read, eventLoop: httpClient.eventLoopGroup.next()).wait())
        defer {
            XCTAssertNoThrow(try XCTUnwrap(fileHandle).close())
            XCTAssertNoThrow(try threadPool.syncShutdownGracefully())
        }

        var input: Input?
        var response: EventLoopFuture<Void>?
        XCTAssertNoThrow(input = try Input(payload: .fileHandle(XCTUnwrap(fileHandle), size: bufferSize, fileIO: fileIO)))
        XCTAssertNoThrow(response = try client.execute(operation: "test", path: "/", httpMethod: "POST", input: XCTUnwrap(input), with: config))

        XCTAssertNoThrow(try awsServer.processRaw { request in
            XCTAssertNil(request.headers["transfer-encoding"])
            XCTAssertEqual(request.headers["Content-Length"], bufferSize.description)
            let requestData = request.body.getData(at: 0, length: request.body.readableBytes)
            XCTAssertEqual(requestData, data)
            let response = AWSTestServer.Response(httpStatus: .ok, headers: [:], body: nil)
            return .result(response)
        })

        XCTAssertNoThrow(try XCTUnwrap(response).wait())
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
        
        let config = createServiceConfig(endpoint: awsServer.address)
        let client = AWSClient(credentialProvider: nil, serviceConfig: config, httpClientProvider: .shared(httpClient))

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
        let response = client.execute(operation: "test", path: "/", httpMethod: "POST", input: input, with: config)

        XCTAssertNoThrow(try awsServer.processRaw { request in
            let bytes = request.body.getBytes(at: 0, length: request.body.readableBytes)
            XCTAssertTrue(bytes == data)
            let response = AWSTestServer.Response(httpStatus: .ok, headers: [:], body: nil)
            return .result(response)
        })

        XCTAssertNoThrow(try response.wait())
    }

    func testProvideHTTPClient() {
        // By default AsyncHTTPClient will follow redirects. This test creates an HTTP client that doesn't follow redirects and
        // provides it to AWSClient
        let awsServer = AWSTestServer(serviceProtocol: .json)
        let httpClientConfig = HTTPClient.Configuration(redirectConfiguration: .init(.disallow))
        let httpClient = HTTPClient(eventLoopGroupProvider: .createNew, configuration: httpClientConfig)
        defer {
            XCTAssertNoThrow(try awsServer.stop())
            XCTAssertNoThrow(try httpClient.syncShutdown())
        }
        let config = createServiceConfig(endpoint: awsServer.address)
        let client = AWSClient(credentialProvider: nil, serviceConfig: config, httpClientProvider: .shared(httpClient))
        let response = client.execute(operation: "test", path: "/", httpMethod: "POST", with: config)

        XCTAssertNoThrow(try awsServer.processRaw { request in
            let response = AWSTestServer.Response(httpStatus: .temporaryRedirect, headers: ["Location": awsServer.address], body: nil)
            return .result(response)
        })

        XCTAssertThrowsError(try response.wait()) { error in
            let awsError = error as? AWSError
            XCTAssertEqual(awsError?.message, "Unhandled Error. Response Code: 307")
        }
    }

    func testRegionEnum() {
        let region = Region(rawValue: "my-region")
        XCTAssertEqual(Region.other("my-region"), region)
        XCTAssertEqual(region.rawValue, "my-region")
    }

    func testClientStopsRetryingAfterMaxRetriesHasBeenReached() {
        let httpClient = AsyncHTTPClient.HTTPClient(eventLoopGroupProvider: .createNew)
        let awsServer = AWSTestServer(serviceProtocol: .json)
        defer {
            XCTAssertNoThrow(try awsServer.stop())
            XCTAssertNoThrow(try httpClient.syncShutdown())
        }
        
        let maxRetries = 3
        let expectedRequests = maxRetries + 1 // retries + first invoke
        
        let config = createServiceConfig(serviceProtocol: .json(version: "1.1"), endpoint: awsServer.address)
        let client = AWSClient(
            credentialProvider: nil,
            serviceConfig: config,
            retryPolicy: ExponentialRetry(base: .milliseconds(200), maxRetries: maxRetries),
            httpClientProvider: .shared(httpClient))
        
        let response = client.execute(operation: "test", path: "/", httpMethod: "POST", with: config)

        var count = 0
        XCTAssertNoThrow(try awsServer.processRaw { request in
            count += 1
            return .error(.internal, continueProcessing: count < expectedRequests)
        })

        XCTAssertThrowsError(try response.wait()) { (error) in
            let serverError = error as? AWSServerError
            
            XCTAssertEqual(serverError, .internalFailure)
            XCTAssertEqual(serverError?.message, AWSTestServer.ErrorType.internal.message)
        }
        
        XCTAssertEqual(count, expectedRequests)
    }

    func testClientRetry() {
        struct Output : AWSDecodableShape, Encodable {
            let s: String
        }
        
        let httpClient = AsyncHTTPClient.HTTPClient(eventLoopGroupProvider: .createNew)
        let awsServer = AWSTestServer(serviceProtocol: .json)
        defer {
            XCTAssertNoThrow(try awsServer.stop())
            XCTAssertNoThrow(try httpClient.syncShutdown())
        }
        let config = createServiceConfig(serviceProtocol: .json(version: "1.1"), endpoint: awsServer.address)
        let client = AWSClient(
            credentialProvider: nil,
            serviceConfig: config,
            retryPolicy: JitterRetry(),
            httpClientProvider: .shared(httpClient))
        let response: EventLoopFuture<Output> = client.execute(operation: "test", path: "/", httpMethod: "POST", with: config)

        var count = 0
        XCTAssertNoThrow(try awsServer.processRaw { request in
            count += 1
            if count < 3 {
                return .error(.notImplemented, continueProcessing: true)
            }
            
            let output = Output(s: "TestOutputString")
            let byteBuffer = try JSONEncoder().encodeAsByteBuffer(output, allocator: ByteBufferAllocator())
            let response = AWSTestServer.Response(httpStatus: .ok, headers: [:], body: byteBuffer)
            return .result(response)
        })

        var output: Output?
        XCTAssertNoThrow(output = try response.wait())
        XCTAssertEqual(output?.s, "TestOutputString")
        XCTAssertEqual(count, 3)
    }

    func testClientAccessDeniedShouldNotBeRetried() {
        struct Output : AWSDecodableShape, Encodable {
            let s: String
        }
        
        let httpClient = AsyncHTTPClient.HTTPClient(eventLoopGroupProvider: .createNew)
        let awsServer = AWSTestServer(serviceProtocol: .json)
        defer {
            XCTAssertNoThrow(try awsServer.stop())
            XCTAssertNoThrow(try httpClient.syncShutdown())
        }
        let config = createServiceConfig(serviceProtocol: .json(version: "1.1"), endpoint: awsServer.address)
        let client = AWSClient(
            credentialProvider: nil,
            serviceConfig: config,
            retryPolicy: JitterRetry(),
            httpClientProvider: .shared(httpClient))

        let response: EventLoopFuture<Output> = client.execute(operation: "test", path: "/", httpMethod: "POST", with: config)

        var count = 0
        XCTAssertNoThrow(try awsServer.processRaw { request in
            count += 1
            return .error(.accessDenied, continueProcessing: false)
        })

        XCTAssertThrowsError(try response.wait()) { (error) in
            let clientError = error as? AWSClientError
            XCTAssertEqual(clientError, .accessDenied)
            XCTAssertEqual(clientError?.message, AWSTestServer.ErrorType.accessDenied.message)
        }
        
        XCTAssertEqual(count, 1)
    }

    func testResponseIsOnTheEventLoopItWasScheduledOn() {
        let eventLoopGroup = MultiThreadedEventLoopGroup(numberOfThreads: 2)
        let httpClient = HTTPClient(eventLoopGroupProvider: .shared(eventLoopGroup))
        let awsServer = AWSTestServer(serviceProtocol: .json)
        defer {
            XCTAssertNoThrow(try httpClient.syncShutdown())
            XCTAssertNoThrow(try eventLoopGroup.syncShutdownGracefully())
            XCTAssertNoThrow(try awsServer.stop())
        }
        let config = createServiceConfig(endpoint: awsServer.address)
        let client = AWSClient(
            credentialProvider: nil,
            serviceConfig: config,
            httpClientProvider: .shared(httpClient))

        let iterations = 10
        let futures = (0..<iterations).map { (_) -> EventLoopFuture<Void> in
            let eventLoop = client.eventLoopGroup.next()
            return client.execute(operation: "test", path: "/", httpMethod: "POST", with: config, on: eventLoop).map {
                XCTAssertTrue(eventLoop.inEventLoop)
            }
        }

        var count = 0
        XCTAssertNoThrow(try awsServer.processRaw { request in
            count += 1
            return .result(.ok, continueProcessing: count < iterations)
        })
        
        XCTAssertNoThrow(try EventLoopFuture.whenAllComplete(futures, on: eventLoopGroup.next()).wait())
        XCTAssertEqual(count, iterations)
    }

    func testMiddlewareIsOnlyAppliedOnce() throws {
        struct URLAppendMiddleware: AWSServiceMiddleware {
            func chain(request: AWSRequest) throws -> AWSRequest {
                var request = request
                request.url.appendPathComponent("test")
                return request
            }
        }
        let config = createServiceConfig(
            service: "testService",
            middlewares: [URLAppendMiddleware()])
        var request: AWSRequest?
        XCTAssertNoThrow(request = try AWSRequest(operation: "test", path: "/", httpMethod: "GET", configuration: config).applyMiddlewares(config.middlewares))
        XCTAssertEqual(request?.url.absoluteString, "https://testService.us-east-1.amazonaws.com/test")
    }
}

/// Error enum for Kinesis
public enum ServiceErrorType: AWSErrorType, Equatable {
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

