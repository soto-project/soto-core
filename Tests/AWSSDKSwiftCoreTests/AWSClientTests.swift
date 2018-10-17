//
//  AWSClient.swift
//  AWSSDKSwift
//
//  Created by Jonathan McAllister on 2018/10/13.
//
//

import Foundation
import NIOHTTP1
import XCTest
@testable import AWSSDKSwiftCore

class AWSClientTests: XCTestCase {

    struct C: AWSShape {
        public static var members: [AWSShapeMember] = [
            AWSShapeMember(label: "value", required: true, type: .string)
        ]

        let value = "<html><body><a href=\"https://redsox.com\">Test</a></body></html>"
    }

    func testCreateAWSRequest() {
        let input = C()

        let sesClient = AWSClient(
            accessKeyId: "foo",
            secretAccessKey: "bar",
            region: nil,
            service: "email",
            serviceProtocol: ServiceProtocol(type: .query),
            apiVersion: "2013-12-01",
            middlewares: [],
            possibleErrorTypes: [SESErrorType.self]
        )

        do {
            let awsRequest = try sesClient.debugCreateAWSRequest(
                operation: "SendEmail",
                path: "/",
                httpMethod: "POST",
                input: input
            )
            XCTAssertEqual(awsRequest.url.absoluteString, "\(sesClient.endpoint)/")
            XCTAssertEqual(String(describing: awsRequest.body), "text(\"Action=SendEmail&Version=2013-12-01&value=%3Chtml%3E%3Cbody%3E%3Ca%20href%3D%22https://redsox.com%22%3ETest%3C/a%3E%3C/body%3E%3C/html%3E\")")
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
            possibleErrorTypes: [KinesisErrorType.self]
        )

        do {
            let awsRequest = try kinesisClient.debugCreateAWSRequest(
                operation: "PutRecord",
                path: "/",
                httpMethod: "POST",
                input: input
            )
            XCTAssertEqual(awsRequest.url.absoluteString, "\(kinesisClient.endpoint)/")
        } catch {
            XCTFail(error.localizedDescription)
        }
    }

    static var allTests : [(String, (AWSClientTests) -> () throws -> Void)] {
        return [
            ("testCreateAWSRequest", testCreateAWSRequest)
        ]
    }
}

/// Error enum for Kinesis
public enum KinesisErrorType: AWSErrorType {
    case resourceNotFoundException(message: String?)
}

extension KinesisErrorType {
    public init?(errorCode: String, message: String?){
        var errorCode = errorCode
        if let index = errorCode.index(of: "#") {
            errorCode = String(errorCode[errorCode.index(index, offsetBy: 1)...])
        }
        switch errorCode {
        case "ResourceNotFoundException":
            self = .resourceNotFoundException(message: message)
        default:
            return nil
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
        if let index = errorCode.index(of: "#") {
            errorCode = String(errorCode[errorCode.index(index, offsetBy: 1)...])
        }
        switch errorCode {
        case "MessageRejected":
            self = .messageRejected(message: message)
        default:
            return nil
        }
    }
}
