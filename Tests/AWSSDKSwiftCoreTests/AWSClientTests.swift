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
import NIOFoundationCompat
import NIOHTTP1
import AWSTestUtils
import AWSXML
@testable import AWSSDKSwiftCore

class AWSClientTests: XCTestCase {

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
        public static let _payloadPath: String = "fooParams"

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
        defer {
            XCTAssertNoThrow(try client.syncShutdown())
        }

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
        defer {
            XCTAssertNoThrow(try client.syncShutdown())
        }

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

    func testPartitionEndpoints() {
        let config = createServiceConfig(
            serviceEndpoints: ["aws-global":"service.aws.amazon.com"],
            partitionEndpoints: [.aws: (endpoint: "aws-global", region: .euwest1)])
        
        XCTAssertEqual(config.region, .euwest1)
        
        var request: AWSRequest?
        XCTAssertNoThrow(request = try AWSRequest(operation: "test", path: "/", httpMethod: "GET", configuration: config))
        XCTAssertEqual(request?.url.absoluteString, "https://service.aws.amazon.com/")
    }

    func testCreateAwsRequestWithKeywordInHeader() {
        struct KeywordRequest: AWSEncodableShape {
            static var _encoding: [AWSMemberEncoding] = [
                AWSMemberEncoding(label: "repeat", location: .header(locationName: "repeat")),
            ]
            let `repeat`: String
        }
        let config = createServiceConfig()
        let request = KeywordRequest(repeat: "Repeat")
        var awsRequest: AWSRequest?
        XCTAssertNoThrow(awsRequest = try AWSRequest(operation: "Keyword", path: "/", httpMethod: "POST", input: request, configuration: config))
        XCTAssertEqual(awsRequest?.httpHeaders["repeat"] as? String, "Repeat")
        XCTAssertTrue(try XCTUnwrap(awsRequest).body.asPayload().isEmpty)
    }

    func testCreateAwsRequestWithKeywordInQuery() {
        struct KeywordRequest: AWSEncodableShape {
            static var _encoding: [AWSMemberEncoding] = [
                AWSMemberEncoding(label: "self", location: .querystring(locationName: "self")),
            ]
            let `self`: String
        }
        let config = createServiceConfig(region: .cacentral1, service: "s3")

        let request = KeywordRequest(self: "KeywordRequest")
        var awsRequest: AWSRequest?
        XCTAssertNoThrow(awsRequest = try AWSRequest(operation: "Keyword", path: "/", httpMethod: "POST", input: request, configuration: config))
        XCTAssertEqual(awsRequest?.url, URL(string:"https://s3.ca-central-1.amazonaws.com/?self=KeywordRequest")!)
        XCTAssertEqual(try XCTUnwrap(awsRequest).body.asByteBuffer(), nil)
    }

    func testCreateNIORequest() {
        let input2 = E()

        let config = createServiceConfig(service: "kinesis", serviceProtocol: .json(version: "1.1"))
        
        var awsRequest: AWSRequest?
        XCTAssertNoThrow(awsRequest = try AWSRequest(
            operation: "PutRecord",
            path: "/",
            httpMethod: "POST",
            input: input2,
            configuration: config)
        )
        
        let signer = AWSSigner(
            credentials: StaticCredential(accessKeyId: "foo", secretAccessKey: "bar"),
            name: config.service,
            region: config.region.rawValue)

        let signedRequest = awsRequest?.createHTTPRequest(signer: signer)
        XCTAssertNotNil(signedRequest)
        XCTAssertEqual(signedRequest?.method, HTTPMethod.POST)
        XCTAssertEqual(signedRequest?.headers["Host"].first, "kinesis.us-east-1.amazonaws.com")
        XCTAssertEqual(signedRequest?.headers["Content-Type"].first, "application/x-amz-json-1.1")
    }

    func testUnsignedClient() {
        let input = E()
        let config = createServiceConfig()
        
        var awsRequest: AWSRequest?
        XCTAssertNoThrow(awsRequest = try AWSRequest(
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

        let request = awsRequest?.createHTTPRequest(signer: signer)
        XCTAssertNil(request?.headers["Authorization"].first)
    }

    func testSignedClient() {
        let input = E()
        let config = createServiceConfig()
        
        let signer = AWSSigner(
            credentials: StaticCredential(accessKeyId: "foo", secretAccessKey: "bar"),
            name: config.service,
            region: config.region.rawValue)

        for httpMethod in ["GET","HEAD","PUT","DELETE","POST","PATCH"] {
            var awsRequest: AWSRequest?

            XCTAssertNoThrow(awsRequest = try AWSRequest(
                operation: "Test",
                path: "/",
                httpMethod: httpMethod,
                input: input,
                configuration: config
            ))

            let request = awsRequest?.createHTTPRequest(signer: signer)
            XCTAssertNotNil(request?.headers["Authorization"].first)
        }
    }

    func testProtocolContentType() throws {
        struct Object: AWSEncodableShape {
            let string: String
        }
        struct Object2: AWSEncodableShape & AWSShapeWithPayload {
            static var _payloadPath = "payload"
            let payload: AWSPayload
            private enum CodingKeys: CodingKey {}
        }
        let object = Object(string: "Name")
        let object2 = Object2(payload: .string("Payload"))

        let config = createServiceConfig(serviceProtocol: .json(version: "1.1"))
        var request: AWSRequest?
        XCTAssertNoThrow(request = try AWSRequest(operation: "test", path: "/", httpMethod: "POST", input: object, configuration: config))
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
        let input = Input(h: "TestHeader")
        let config = createServiceConfig()
        var request: AWSRequest?
        XCTAssertNoThrow(request = try AWSRequest(operation: "Test", path: "/", httpMethod: "GET", input: input, configuration: config))
        XCTAssertEqual(request?.httpHeaders["header-member"] as? String, "TestHeader")
    }

    func testQueryEncoding() {
        struct Input: AWSEncodableShape {
            static let _encoding = [AWSMemberEncoding(label: "q", location: .querystring(locationName: "query"))]
            let q: String
        }
        let input = Input(q: "=3+5897^sdfjh&")
        let config = createServiceConfig()
        var request: AWSRequest?
        XCTAssertNoThrow(request = try AWSRequest(operation: "Test", path: "/", httpMethod: "GET", input: input, configuration: config))
        XCTAssertEqual(request?.url.absoluteString, "https://test.us-east-1.amazonaws.com/?query=%3D3%2B5897%5Esdfjh%26")
    }

    func testQueryEncodedArray() {
        struct Input: AWSEncodableShape {
            static let _encoding = [AWSMemberEncoding(label: "q", location: .querystring(locationName: "query"))]
            let q: [String]
        }
        let input = Input(q: ["=3+5897^sdfjh&", "test"])
        let config = createServiceConfig()
        
        var request: AWSRequest?
        XCTAssertNoThrow(request = try AWSRequest(operation: "Test", path: "/", httpMethod: "GET", input: input, configuration: config))
        XCTAssertEqual(request?.url.absoluteString, "https://test.us-east-1.amazonaws.com/?query=%3D3%2B5897%5Esdfjh%26&query=test")
    }

    func testQueryEncodedDictionary() {
        struct Input: AWSEncodableShape {
            static let _encoding = [AWSMemberEncoding(label: "q", location: .querystring(locationName: "query"))]
            let q: [String: Int]
        }
        let input = Input(q: ["one": 1, "two": 2])
        let config = createServiceConfig(region: .useast2, service: "myservice")
        var request: AWSRequest?
        XCTAssertNoThrow(request = try AWSRequest(operation: "Test", path: "/", httpMethod: "GET", input: input, configuration: config))
        XCTAssertEqual(request?.url.absoluteString, "https://myservice.us-east-2.amazonaws.com/?one=1&two=2")
    }

    func testURIEncoding() {
        struct Input: AWSEncodableShape {
            static let _encoding = [AWSMemberEncoding(label: "u", location: .uri(locationName: "key"))]
            let u: String
        }
        let input = Input(u: "MyKey")
        let config = createServiceConfig(region: .cacentral1, service: "s3")
        var request: AWSRequest?
        XCTAssertNoThrow(request = try AWSRequest(operation: "Test", path: "/{key}", httpMethod: "GET", input: input, configuration: config))
        XCTAssertEqual(request?.url.absoluteString, "https://s3.ca-central-1.amazonaws.com/MyKey")
    }

    func testCreateWithXMLNamespace() {
        struct Input: AWSEncodableShape {
            public static let _xmlNamespace: String? = "https://test.amazonaws.com/doc/2020-03-11/"
            let number: Int
        }
        let input = Input(number: 5)
        let xmlConfig = createServiceConfig(serviceProtocol: .restxml)
        var request: AWSRequest?
        XCTAssertNoThrow(request = try AWSRequest(operation: "Test", path: "/", httpMethod: "GET", input: input, configuration: xmlConfig))
        guard case .xml(let element) = request?.body else {
            return XCTFail("Shouldn't get here")
        }
        XCTAssertEqual(element.xmlString, "<Input xmlns=\"https://test.amazonaws.com/doc/2020-03-11/\"><number>5</number></Input>")
    }


    func testCreateWithPayloadAndXMLNamespace() {
        struct Payload: AWSEncodableShape {
            public static let _xmlNamespace: String? = "https://test.amazonaws.com/doc/2020-03-11/"
            let number: Int
        }
        struct Input: AWSEncodableShape & AWSShapeWithPayload {
            public static let _payloadPath: String = "payload"
            let payload: Payload
        }
        let input = Input(payload: Payload(number: 5))
        let xmlConfig = createServiceConfig(serviceProtocol: .restxml)
        var request: AWSRequest?
        XCTAssertNoThrow(request = try AWSRequest(operation: "Test", path: "/", httpMethod: "GET", input: input, configuration: xmlConfig))
        guard case .xml(let element) = request?.body else {
            return XCTFail("Shouldn't get here")
        }
        XCTAssertEqual(element.xmlString, "<Payload xmlns=\"https://test.amazonaws.com/doc/2020-03-11/\"><number>5</number></Payload>")
    }

    func testDataInJsonPayload() {
        struct DataContainer: AWSEncodableShape {
            let data: Data
        }
        struct J: AWSEncodableShape & AWSShapeWithPayload {
            public static let _payloadPath: String = "dataContainer"
            let dataContainer: DataContainer
        }
        let input = J(dataContainer: DataContainer(data: Data("test data".utf8)))
        let jsonConfig = createServiceConfig(serviceProtocol: .json(version: "1.1"))
        XCTAssertNoThrow(try AWSRequest(operation: "PutRecord",path: "/",httpMethod: "POST", input: input, configuration: jsonConfig))
    }

    func testHeadersAreWritten() {
        let awsServer = AWSTestServer(serviceProtocol: .json)
        let elg = MultiThreadedEventLoopGroup(numberOfThreads: 1)
        let httpClient = HTTPClient(eventLoopGroupProvider: .shared(elg))
        defer {
            try? awsServer.stop()
            try? httpClient.syncShutdown()
            try? elg.syncShutdownGracefully()
        }
        let client = createAWSClient(accessKeyId: "foo", secretAccessKey: "bar", serviceProtocol: .json(version: "1.1"), endpoint: awsServer.address, httpClientProvider: .shared(httpClient))
        defer {
            XCTAssertNoThrow(try client.syncShutdown())
        }
        let response: EventLoopFuture<AWSTestServer.HTTPBinResponse> = client.send(operation: "test", path: "/", httpMethod: "POST")

        XCTAssertNoThrow(try awsServer.httpBin())
        var httpBinResponse: AWSTestServer.HTTPBinResponse? = nil
        XCTAssertNoThrow(httpBinResponse = try response.wait())
        let httpHeaders = httpBinResponse.map { HTTPHeaders($0.headers.map { ($0, $1) }) }

        XCTAssertEqual(httpHeaders?["Content-Length"].first, "0")
        XCTAssertEqual(httpHeaders?["Content-Type"].first, "application/x-amz-json-1.1")
        XCTAssertNotNil(httpHeaders?["Authorization"].first)
        XCTAssertNotNil(httpHeaders?["X-Amz-Date"].first)
        XCTAssertEqual(httpHeaders?["User-Agent"].first, "AWSSDKSwift/5.0")
        XCTAssertEqual(httpHeaders?["Host"].first, "localhost:\(awsServer.serverPort)")
    }

    func testClientNoInputNoOutput() {
        do {
            let awsServer = AWSTestServer(serviceProtocol: .json)
            let client = createAWSClient(accessKeyId: "", secretAccessKey: "", serviceProtocol: .json(version: "1.1"), endpoint: awsServer.address)
            defer {
                XCTAssertNoThrow(try client.syncShutdown())
                XCTAssertNoThrow(try awsServer.stop())
            }
            let response = client.send(operation: "test", path: "/", httpMethod: "POST")

            try awsServer.processRaw { request in
                let response = AWSTestServer.Response(httpStatus: .ok, headers: [:], body: nil)
                return .result(response)
            }

            try response.wait()
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
            defer {
                XCTAssertNoThrow(try client.syncShutdown())
                XCTAssertNoThrow(try awsServer.stop())
            }
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
            defer {
                XCTAssertNoThrow(try client.syncShutdown())
                XCTAssertNoThrow(try awsServer.stop())
            }
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
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testEC2ClientRequest() {
        struct Input: AWSEncodableShape {
            let array: [String]
        }
        let input = Input(array: ["entry1", "entry2"])
        let config = createServiceConfig(serviceProtocol: .ec2, apiVersion: "2013-12-02")
        var request: AWSRequest?
        XCTAssertNoThrow(request = try AWSRequest(operation: "Test", path: "/", httpMethod: "GET", input: input, configuration: config))
        XCTAssertEqual(request?.body.asString(), "Action=Test&Array.1=entry1&Array.2=entry2&Version=2013-12-02")
    }

    func testRequestStreaming(client: AWSClient, server: AWSTestServer, bufferSize: Int, blockSize: Int) throws {
        struct Input : AWSEncodableShape & AWSShapeWithPayload {
            static var _payloadPath: String = "payload"
            static var _payloadOptions: PayloadOptions = [.allowStreaming, .raw]
            let payload: AWSPayload
            private enum CodingKeys: CodingKey {}
        }
        let data = createRandomBuffer(45,9182, size: bufferSize)
        var byteBuffer = ByteBufferAllocator().buffer(capacity: data.count)
        byteBuffer.writeBytes(data)

        let payload = AWSPayload.stream(size: bufferSize) { eventLoop in
            let size = min(blockSize, byteBuffer.readableBytes)
            // don't ask for 0 bytes
            XCTAssertNotEqual(size, 0)
            let buffer = byteBuffer.readSlice(length: size)!
            return eventLoop.makeSucceededFuture(buffer)
        }
        let input = Input(payload: payload)
        let response = client.send(operation: "test", path: "/", httpMethod: "POST", input: input)

        try server.processRaw { request in
            let bytes = request.body.getBytes(at: 0, length: request.body.readableBytes)
            XCTAssertEqual(bytes, data)
            let response = AWSTestServer.Response(httpStatus: .ok, headers: [:], body: nil)
            return .result(response)
        }

        try response.wait()
    }

    func testRequestStreaming() {
        let awsServer = AWSTestServer(serviceProtocol: .json)
        let httpClient = HTTPClient(eventLoopGroupProvider: .createNew)
        let client = createAWSClient(accessKeyId: "", secretAccessKey: "", endpoint: awsServer.address, httpClientProvider: .shared(httpClient))
        defer {
            XCTAssertNoThrow(try awsServer.stop())
            XCTAssertNoThrow(try client.syncShutdown())
            XCTAssertNoThrow(try httpClient.syncShutdown())
        }

        XCTAssertNoThrow(try testRequestStreaming(client: client, server: awsServer, bufferSize: 128*1024, blockSize: 16*1024))
        XCTAssertNoThrow(try testRequestStreaming(client: client, server: awsServer, bufferSize: 128*1024, blockSize: 17*1024))
        XCTAssertNoThrow(try testRequestStreaming(client: client, server: awsServer, bufferSize: 18*1024, blockSize: 47*1024))
    }

    func testRequestS3Streaming() {
        let awsServer = AWSTestServer(serviceProtocol: .json)
        let httpClient = HTTPClient(eventLoopGroupProvider: .createNew)
        let client = createAWSClient(accessKeyId: "foo", secretAccessKey: "bar", service: "s3", endpoint: awsServer.address, httpClientProvider: .shared(httpClient))
        defer {
            XCTAssertNoThrow(try client.syncShutdown())
            XCTAssertNoThrow(try awsServer.stop())
            XCTAssertNoThrow(try httpClient.syncShutdown())
        }

        XCTAssertNoThrow(try testRequestStreaming(client: client, server: awsServer, bufferSize: 128*1024, blockSize: 16*1024))
        XCTAssertNoThrow(try testRequestStreaming(client: client, server: awsServer, bufferSize: 81*1024, blockSize: 16*1024))
        XCTAssertNoThrow(try testRequestStreaming(client: client, server: awsServer, bufferSize: 128*1024, blockSize: S3ChunkedStreamReader.bufferSize))
        XCTAssertNoThrow(try testRequestStreaming(client: client, server: awsServer, bufferSize: 130*1024, blockSize: S3ChunkedStreamReader.bufferSize))
        XCTAssertNoThrow(try testRequestStreaming(client: client, server: awsServer, bufferSize: 128*1024, blockSize: 17*1024))
        XCTAssertNoThrow(try testRequestStreaming(client: client, server: awsServer, bufferSize: 18*1024, blockSize: 47*1024))
    }

    func testRequestStreamingTooMuchData() {
        struct Input : AWSEncodableShape & AWSShapeWithPayload {
            static var _payloadPath: String = "payload"
            static var _payloadOptions: PayloadOptions = [.allowStreaming]
            let payload: AWSPayload
            private enum CodingKeys: CodingKey {}
        }

        let awsServer = AWSTestServer(serviceProtocol: .json)
        let httpClient = HTTPClient(eventLoopGroupProvider: .createNew)
        let client = createAWSClient(accessKeyId: "", secretAccessKey: "", endpoint: awsServer.address, httpClientProvider: .shared(httpClient))
        defer {
            // ignore error
            try? awsServer.stop()
            XCTAssertNoThrow(try client.syncShutdown())
            XCTAssertNoThrow(try httpClient.syncShutdown())
        }
        do {

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
            static var _payloadPath: String = "payload"
            static var _payloadOptions: PayloadOptions = [.allowStreaming]
            let payload: AWSPayload
            private enum CodingKeys: CodingKey {}
        }

        let awsServer = AWSTestServer(serviceProtocol: .json)
        let httpClient = HTTPClient(eventLoopGroupProvider: .createNew)
        let client = createAWSClient(accessKeyId: "", secretAccessKey: "", endpoint: awsServer.address, httpClientProvider: .shared(httpClient))
        defer {
            XCTAssertNoThrow(try awsServer.stop())
            XCTAssertNoThrow(try client.syncShutdown())
            XCTAssertNoThrow(try httpClient.syncShutdown())
        }
        do {
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
            static var _payloadPath: String = "payload"
            static var _payloadOptions: PayloadOptions = [.allowStreaming, .allowChunkedStreaming, .raw]
            let payload: AWSPayload
            private enum CodingKeys: CodingKey {}
        }

        let awsServer = AWSTestServer(serviceProtocol: .json)
        let httpClient = HTTPClient(eventLoopGroupProvider: .createNew)
        let client = createAWSClient(accessKeyId: "", secretAccessKey: "", endpoint: awsServer.address, httpClientProvider: .shared(httpClient))
        defer {
            XCTAssertNoThrow(try awsServer.stop())
            XCTAssertNoThrow(try client.syncShutdown())
            XCTAssertNoThrow(try httpClient.syncShutdown())
        }
        do {

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
            let client = createAWSClient(accessKeyId: "", secretAccessKey: "", serviceProtocol: .json(version: "1.1"), endpoint: awsServer.address, httpClientProvider: .shared(httpClient))
            defer {
                XCTAssertNoThrow(try awsServer.stop())
                XCTAssertNoThrow(try client.syncShutdown())
                XCTAssertNoThrow(try httpClient.syncShutdown())
            }
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
            let client = createAWSClient(accessKeyId: "", secretAccessKey: "", serviceProtocol: .json(version: "1.1"), endpoint: awsServer.address, retryPolicy: ExponentialRetry(base: .milliseconds(200)), httpClientProvider: .shared(httpClient))
            defer {
                XCTAssertNoThrow(try awsServer.stop())
                XCTAssertNoThrow(try client.syncShutdown())
                XCTAssertNoThrow(try httpClient.syncShutdown())
            }
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
            let client = createAWSClient(
                accessKeyId: "",
                secretAccessKey: "",
                serviceProtocol: .json(version: "1.1"),
                endpoint: awsServer.address,
                retryPolicy: JitterRetry(),
                httpClientProvider: .shared(httpClient)
            )
            defer {
                XCTAssertNoThrow(try awsServer.stop())
                XCTAssertNoThrow(try client.syncShutdown())
                XCTAssertNoThrow(try httpClient.syncShutdown())
            }
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
            let client = createAWSClient(
                accessKeyId: "",
                secretAccessKey: "",
                serviceProtocol: .json(version: "1.1"),
                endpoint: awsServer.address,
                retryPolicy: JitterRetry(),
                httpClientProvider: .shared(httpClient)
            )
            defer {
                XCTAssertNoThrow(try awsServer.stop())
                XCTAssertNoThrow(try client.syncShutdown())
                XCTAssertNoThrow(try httpClient.syncShutdown())
            }
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
            let client = createAWSClient(
                accessKeyId: "",
                secretAccessKey: "",
                endpoint: awsServer.address,
                httpClientProvider: .shared(httpClient)
            )
            defer {
                XCTAssertNoThrow(try client.syncShutdown())
                XCTAssertNoThrow(try httpClient.syncShutdown())
                XCTAssertNoThrow(try eventLoopGroup.syncShutdownGracefully())
                XCTAssertNoThrow(try awsServer.stop())
            }
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
        
        let config = createServiceConfig(middlewares: [URLAppendMiddleware()])
        var request: AWSRequest?
        XCTAssertNoThrow(request = try AWSRequest(
            operation: "test",
            path: "/",
            httpMethod: "GET",
            configuration: config
        ).applyMiddlewares(config.middlewares))
        XCTAssertEqual(request?.url.absoluteString, "https://test.us-east-1.amazonaws.com/test")
    }

    func testStreamingResponse() {
        struct Input : AWSEncodableShape {
        }
        struct Output : AWSDecodableShape & Encodable {
            static let _encoding = [AWSMemberEncoding(label: "test", location: .header(locationName: "test"))]
            let test: String
        }
        let data = createRandomBuffer(45, 109, size: 128*1024)

        do {
            let awsServer = AWSTestServer(serviceProtocol: .json)
            let eventLoopGroup = MultiThreadedEventLoopGroup(numberOfThreads: 5)
            let httpClient = HTTPClient(eventLoopGroupProvider: .shared(eventLoopGroup))
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
            defer {
                XCTAssertNoThrow(try client.syncShutdown())
                XCTAssertNoThrow(try httpClient.syncShutdown())
                XCTAssertNoThrow(try eventLoopGroup.syncShutdownGracefully())
                XCTAssertNoThrow(try awsServer.stop())
            }
            var count = 0
            let response: EventLoopFuture<Output> = client.send(operation: "test", path: "/", httpMethod: "GET", input: Input()) { (payload: ByteBuffer, eventLoop: EventLoop) in
                let payloadSize = payload.readableBytes
                let slice = Data(data[count..<(count+payloadSize)])
                let payloadData = payload.getData(at: 0, length: payload.readableBytes)
                XCTAssertEqual(slice, payloadData)
                count += payloadSize
                return eventLoop.makeSucceededFuture(())
            }

            try awsServer.processRaw { request in
                var byteBuffer = ByteBufferAllocator().buffer(capacity: 128*1024)
                byteBuffer.writeBytes(data)
                let response = AWSTestServer.Response(httpStatus: .ok, headers: ["test":"TestHeader"], body: byteBuffer)
                return .result(response)
            }

            let result = try response.wait()
            XCTAssertEqual(result.test, "TestHeader")
            XCTAssertEqual(count, 128*1024)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }

    }
}
