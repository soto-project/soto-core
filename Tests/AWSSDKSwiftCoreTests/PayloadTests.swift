//
//  PayloadTests.swift
//  AWSSDKSwift
//
//  Created by Adam Fowler 2020/03/01
//
//

import NIO
import XCTest
@testable import AWSSDKSwiftCore

class PayloadTests: XCTestCase {

    func testDataRequestPayload() {
        struct DataPayload: AWSShape {
            static var payloadPath: String? = "data"
            let data: AWSPayload
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
                eventLoopGroupProvider: .useAWSClientShared
            )
            let input = DataPayload(data: .string("testDataPayload"))
            let response = client.send(operation: "test", path: "/", httpMethod: "POST", input: input)

            try awsServer.process { request in
                XCTAssertEqual(request.body.getString(at: 0, length: request.body.readableBytes), "testDataPayload")
                return AWSTestServer.Result(output: .ok, continueProcessing: false)
            }

            try response.wait()
            try awsServer.stop()
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }
    
    func testByteBufferRequestPayload() {
        struct DataPayload: AWSShape {
            static var payloadPath: String? = "data"
            let data: AWSPayload
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
                eventLoopGroupProvider: .useAWSClientShared
            )
            var byteBuffer = ByteBufferAllocator().buffer(capacity: 32)
            byteBuffer.writeString("testByteBufferPayload")
            let input = DataPayload(data:.byteBuffer(byteBuffer))
            let response = client.send(operation: "test", path: "/", httpMethod: "POST", input: input)

            try awsServer.process { request in
                XCTAssertEqual(request.body.getString(at: 0, length: request.body.readableBytes), "testByteBufferPayload")
                return AWSTestServer.Result(output: .ok, continueProcessing: false)
            }

            try response.wait()
            try awsServer.stop()
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }
    
    static var allTests : [(String, (PayloadTests) -> () throws -> Void)] {
        return [
            ("testDataRequestPayload", testDataRequestPayload),
            ("testByteBufferRequestPayload", testByteBufferRequestPayload),
        ]
    }
}
