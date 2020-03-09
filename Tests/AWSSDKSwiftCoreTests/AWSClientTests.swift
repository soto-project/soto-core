//
//  AWSClient.swift
//  AWSSDKSwift
//
//  Created by Jonathan McAllister on 2018/10/13.
//
//

import XCTest
import NIO
import NIOHTTP1
@testable import AWSSDKSwiftCore

class AWSClientTests: XCTestCase {

    static var allTests : [(String, (AWSClientTests) -> () throws -> Void)] {
        return [
            ("testGetCredential", testGetCredential),
            ("testCreateAWSRequest", testCreateAWSRequest),
            ("testCreateNIORequest", testCreateNIORequest),
            ("testValidateCode", testValidateCode),
            ("testValidateXMLResponse", testValidateXMLResponse),
            ("testValidateXMLPayloadResponse", testValidateXMLPayloadResponse),
            ("testValidateXMLError", testValidateXMLError),
            ("testValidateJSONResponse", testValidateJSONResponse),
            ("testValidateJSONPayloadResponse", testValidateJSONPayloadResponse),
            ("testValidateJSONError", testValidateJSONError),
            ("testProcessHAL", testProcessHAL),
            ("testDataInJsonPayload", testDataInJsonPayload)
        ]
    }

    struct C: AWSShape {
        public static var _members: [AWSShapeMember] = [
            AWSShapeMember(label: "value", location: .header(locationName: "value"), required: true, type: .string)
        ]

        let value = "<html><body><a href=\"https://redsox.com\">Test</a></body></html>"

        private enum CodingKeys: String, CodingKey {
            case value = "Value"
        }
    }

    struct E: AWSShape {
        public static var _members: [AWSShapeMember] = [
            AWSShapeMember(label: "Member", required: true, type: .list),
        ]

        let Member = ["memberKey": "memberValue", "memberKey2" : "memberValue2"]

        private enum CodingKeys: String, CodingKey {
            case Member = "Member"
        }
    }

    struct F: AWSShape {
        public static let payloadPath: String? = "fooParams"

        public static var _members: [AWSShapeMember] = [
            AWSShapeMember(label: "Member", required: true, type: .list),
            AWSShapeMember(label: "fooParams", required: false, type: .structure),
        ]

        public let fooParams: E?

        public init(fooParams: E? = nil) {
            self.fooParams = fooParams
        }

        private enum CodingKeys: String, CodingKey {
            case fooParams = "fooParams"
        }
    }


    func testGetCredential() {
        let eventLoopGroup = MultiThreadedEventLoopGroup(numberOfThreads: 1)
        defer { XCTAssertNoThrow(try eventLoopGroup.syncShutdownGracefully()) }

        let sesClient = AWSClient(
            accessKeyId: "key",
            secretAccessKey: "secret",
            region: nil,
            service: "email",
            serviceProtocol: ServiceProtocol(type: .query),
            apiVersion: "2013-12-01",
            middlewares: [],
            possibleErrorTypes: [SESErrorType.self],
            eventLoopGroupProvider: .shared(eventLoopGroup)
        )

        do {
            let credentialForSignature = try sesClient.signer.manageCredential(eventLoopGroup: eventLoopGroup).wait()
            XCTAssertEqual(credentialForSignature.accessKeyId, "key")
            XCTAssertEqual(credentialForSignature.secretAccessKey, "secret")
        } catch {
            XCTFail(error.localizedDescription)
        }
    }

    struct G: AWSShape {
        public static let payloadPath: String? = "data"

        public static var members: [AWSShapeMember] = [
            AWSShapeMember(label: "data", required: true, type: .blob)
        ]

        public let data: Data

        public init(data: Data) {
            self.data = data
        }

        private enum CodingKeys: String, CodingKey {
        case data = "data"
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
        eventLoopGroupProvider: .useAWSClientShared
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
        eventLoopGroupProvider: .useAWSClientShared
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
        eventLoopGroupProvider: .useAWSClientShared
    )

    func testCreateAWSRequest() {
        let eventLoopGroup = MultiThreadedEventLoopGroup(numberOfThreads: 1)
        defer { XCTAssertNoThrow(try eventLoopGroup.syncShutdownGracefully()) }

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
            XCTAssertEqual(String(describing: awsRequest.body), "text(\"Action=SendEmail&Value=%3Chtml%3E%3Cbody%3E%3Ca%20href%3D%22https://redsox.com%22%3ETest%3C/a%3E%3C/body%3E%3C/html%3E&Version=2013-12-01\")")
            let nioRequest = try awsRequest.toNIORequest()
            XCTAssertEqual(nioRequest.head.headers["Content-Type"][0], "application/x-www-form-urlencoded; charset=utf-8")
            XCTAssertEqual(nioRequest.head.method, HTTPMethod.POST)
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
            eventLoopGroupProvider: .shared(eventLoopGroup)
        )

        do {
            let awsRequest = try kinesisClient.createAWSRequest(
                operation: "PutRecord",
                path: "/",
                httpMethod: "POST",
                input: input2
            )
            XCTAssertEqual(awsRequest.url.absoluteString, "\(kinesisClient.endpoint)/")

            if let bodyAsData = awsRequest.body.asData(), let parsedBody = try JSONSerialization.jsonObject(with: bodyAsData, options: []) as? [String:Any] {
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

            let nioRequest = try awsRequest.toNIORequest()
            XCTAssertEqual(nioRequest.head.headers["Content-Type"][0], "application/x-amz-json-1.1")
            XCTAssertEqual(nioRequest.head.method, HTTPMethod.POST)
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
            let nioRequest = try awsRequest.toNIORequest()
            XCTAssertEqual(nioRequest.head.method, HTTPMethod.GET)
            XCTAssertEqual(nioRequest.body, Data())
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
            if let xmlData = awsRequest.body.asData() {
                let document = try XML.Document(data:xmlData)
                XCTAssertNotNil(document.rootElement())
                let payload = try XMLDecoder().decode(E.self, from: document.rootElement()!)
                XCTAssertEqual(payload.Member["memberKey2"], "memberValue2")
            }
            let nioRequest = try awsRequest.toNIORequest()
            XCTAssertEqual(nioRequest.head.method, HTTPMethod.POST)
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
            if let jsonData = awsRequest.body.asData() {
                let jsonBody = try! JSONSerialization.jsonObject(with: jsonData, options: .allowFragments) as! [String:Any]
                let fromJson = jsonBody["Member"]! as! [String: String]
                XCTAssertEqual(fromJson["memberKey"], "memberValue")
            }

        } catch {
            XCTFail(error.localizedDescription)
        }
    }

    func testCreateAwsRequestWithKeywordInHeader() {
        struct KeywordRequest: AWSShape {
            static var _members: [AWSShapeMember] = [
                AWSShapeMember(label: "repeat", location: .header(locationName: "repeat"), required: true, type: .string),
            ]
            let `repeat`: String
        }
        do {
            let request = KeywordRequest(repeat: "Repeat")
            let awsRequest = try s3Client.createAWSRequest(operation: "Keyword", path: "/", httpMethod: "POST", input: request)
            XCTAssertEqual(awsRequest.httpHeaders["repeat"] as? String, "Repeat")
        } catch {
            XCTFail(error.localizedDescription)
        }
    }

    func testCreateAwsRequestWithKeywordInQuery() {
        struct KeywordRequest: AWSShape {
            static var _members: [AWSShapeMember] = [
                AWSShapeMember(label: "self", location: .querystring(locationName: "self"), required: true, type: .string),
            ]
            let `self`: String
        }
        do {
            let request = KeywordRequest(self: "KeywordRequest")
            let awsRequest = try s3Client.createAWSRequest(operation: "Keyword", path: "/", httpMethod: "POST", input: request)
            XCTAssertEqual(awsRequest.url, URL(string:"https://s3.amazonaws.com/?self=KeywordRequest")!)
        } catch {
            XCTFail(error.localizedDescription)
        }
    }

    func testCreateNIORequest() {
        let eventLoopGroup = MultiThreadedEventLoopGroup(numberOfThreads: 1)
        defer { XCTAssertNoThrow(try eventLoopGroup.syncShutdownGracefully()) }

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
            eventLoopGroupProvider: .shared(eventLoopGroup)
        )

        do {
            let awsRequest = try kinesisClient.createAWSRequest(
                operation: "PutRecord",
                path: "/",
                httpMethod: "POST",
                input: input2
            )

            let nioRequest = try kinesisClient.createNioRequest(awsRequest)
            XCTAssertEqual(nioRequest.head.method, HTTPMethod.POST)
            if let host = nioRequest.head.headers.first(where: { $0.name == "Host" }) {
                XCTAssertEqual(host.value, "kinesis.us-east-1.amazonaws.com")
            }
            if let contentType = nioRequest.head.headers.first(where: { $0.name == "Content-Type" }) {
                XCTAssertEqual(contentType.value, "application/x-amz-json-1.1")
            }
            if let xAmzTarget = nioRequest.head.headers.first(where: { $0.name == "x-amz-target" }) {
                XCTAssertEqual(xAmzTarget.value, "Kinesis_20131202.PutRecord")
            }

        } catch {
            XCTFail(error.localizedDescription)
        }
    }

    func testValidateCode() {
        let response = HTTPClient.Response(
            head: HTTPResponseHead(
                version: HTTPVersion(major: 1, minor: 1),
                status: HTTPResponseStatus(statusCode: 200)
            ),
            body: Data()
        )
        do {
            try s3Client.validate(response: response)
        } catch {
            XCTFail(error.localizedDescription)
        }

        let failResponse = HTTPClient.Response(
            head: HTTPResponseHead(
                version: HTTPVersion(major: 1, minor: 1),
                status: HTTPResponseStatus(statusCode: 403)
            ),
            body: Data()
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
        let response = HTTPClient.Response(
            head: HTTPResponseHead(
                version: HTTPVersion(major: 1, minor: 1),
                status: HTTPResponseStatus(statusCode: 200)
            ),
            body: "<Output><name>hello</name></Output>".data(using: .utf8)!
        )
        do {
            let output : Output = try s3Client.validate(operation: "Output", response: response)
            XCTAssertEqual(output.name, "hello")
        } catch {
            XCTFail(error.localizedDescription)
        }
    }

    func testValidateXMLPayloadResponse() {
        class Output : AWSShape {
            static let payloadPath: String? = "name"
            let name : String
        }
        let response = HTTPClient.Response(
            head: HTTPResponseHead(
                version: HTTPVersion(major: 1, minor: 1),
                status: HTTPResponseStatus(statusCode: 200)
            ),
            body: "<name>hello</name>".data(using: .utf8)!
        )
        do {
            let output : Output = try s3Client.validate(operation: "Output", response: response)
            XCTAssertEqual(output.name, "hello")
        } catch {
            XCTFail(error.localizedDescription)
        }
    }

    func testValidateXMLError() {
        let response = HTTPClient.Response(
            head: HTTPResponseHead(
                version: HTTPVersion(major: 1, minor: 1),
                status: HTTPResponseStatus(statusCode: 404)
            ),
            body: "<Error><Code>NoSuchKey</Code><Message>It doesn't exist</Message></Error>".data(using: .utf8)!
        )
        do {
            try s3Client.validate(response: response)
            XCTFail("Should not get here")
        } catch S3ErrorType.noSuchKey(let message) {
            XCTAssertEqual(message, "Message: It doesn't exist")
        } catch {
            XCTFail("Throwing the wrong error")
        }
    }

    func testValidateRawResponseError() {
        class Output : AWSShape {
            static let payloadPath: String? = "output"
            public static var _members: [AWSShapeMember] = [AWSShapeMember(label: "output", required: true, type: .blob)]
            let output : Data
        }
        do {
            let response = HTTPClient.Response(
                head: HTTPResponseHead(
                    version: HTTPVersion(major: 1, minor: 1),
                    status: HTTPResponseStatus(statusCode: 404)
                ),
                body: "<Error><Code>NoSuchKey</Code><Message>It doesn't exist</Message></Error>".data(using: .utf8)!
            )
            let _: Output = try s3Client.validate(operation: "TestOperation", response: response)
            XCTFail("Shouldn't get here")
        } catch S3ErrorType.noSuchKey(_) {
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }


    func testValidateJSONResponse() {
        class Output : AWSShape {
            let name : String
        }
        let response = HTTPClient.Response(
            head: HTTPResponseHead(
                version: HTTPVersion(major: 1, minor: 1),
                status: HTTPResponseStatus(statusCode: 200)
            ),
            body: "{\"name\":\"hello\"}".data(using: .utf8)!
        )
        do {
            let output : Output = try kinesisClient.validate(operation: "Output", response: response)
            XCTAssertEqual(output.name, "hello")
        } catch {
            XCTFail(error.localizedDescription)
        }
    }

    func testValidateJSONPayloadResponse() {
        class Output2 : AWSShape {
            let name : String
        }
        class Output : AWSShape {
            static let payloadPath: String? = "output2"
            let output2 : Output2
        }
        let response = HTTPClient.Response(
            head: HTTPResponseHead(
                version: HTTPVersion(major: 1, minor: 1),
                status: HTTPResponseStatus(statusCode: 200)
            ),
            body: "{\"name\":\"hello\"}".data(using: .utf8)!
        )
        do {
            let output : Output = try kinesisClient.validate(operation: "Output", response: response)
            XCTAssertEqual(output.output2.name, "hello")
        } catch {
            XCTFail(error.localizedDescription)
        }
    }

    func testValidateJSONError() {
        let response = HTTPClient.Response(
            head: HTTPResponseHead(
                version: HTTPVersion(major: 1, minor: 1),
                status: HTTPResponseStatus(statusCode: 404)
            ),
            body: "{\"__type\":\"ResourceNotFoundException\", \"message\": \"Donald Where's Your Troosers?\"}".data(using: .utf8)!
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
            public static var _members: [AWSShapeMember] = [
                AWSShapeMember(label: "s", required: true, type: .string),
                AWSShapeMember(label: "i", required: true, type: .integer)
            ]
            let s: String
            let i: Int
        }
        class Output2 : AWSShape {
            public static var _members: [AWSShapeMember] = [
                AWSShapeMember(label: "a", location: .body(locationName: "a"), required: true, type: .list),
                AWSShapeMember(label: "d", required: true, type: .double),
                AWSShapeMember(label: "b", required: true, type: .boolean),
            ]
            let a: [Output]
            let d: Double
            let b: Bool
        }
        let response = HTTPClient.Response(
            head: HTTPResponseHead(
                version: HTTPVersion(major: 1, minor: 1),
                status: HTTPResponseStatus(statusCode: 200),
                headers: ["Content-Type":"application/hal+json"]
            ),
            body: """
                {"_embedded": {"a": [{"s":"Hello", "i":1234}, {"s":"Hello2", "i":12345}]}, "d":3.14, "b":true}
                """.data(using: .utf8)!
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
            public static var _members: [AWSShapeMember] = [
                AWSShapeMember(label: "dataContainer", required: false, type: .structure),
            ]
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
}

/// Error enum for Kinesis
public enum KinesisErrorType: AWSErrorType {
    case resourceNotFoundException(message: String?)
}

extension KinesisErrorType {
    public init?(errorCode: String, message: String?){
        var errorCode = errorCode
        if let index = errorCode.firstIndex(of: "#") {
            errorCode = String(errorCode[errorCode.index(index, offsetBy: 1)...])
        }
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

/// Error enum for SES
public enum SESErrorType: AWSErrorType {
    case messageRejected(message: String?)
}

extension SESErrorType {
    public init?(errorCode: String, message: String?){
        var errorCode = errorCode
        if let index = errorCode.firstIndex(of: "#") {
            errorCode = String(errorCode[errorCode.index(index, offsetBy: 1)...])
        }
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

/// Error enum for S3
public enum S3ErrorType: AWSErrorType {
    case noSuchKey(message: String?)
}

extension S3ErrorType {
    public init?(errorCode: String, message: String?){
        var errorCode = errorCode
        if let index = errorCode.firstIndex(of: "#") {
            errorCode = String(errorCode[errorCode.index(index, offsetBy: 1)...])
        }
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
