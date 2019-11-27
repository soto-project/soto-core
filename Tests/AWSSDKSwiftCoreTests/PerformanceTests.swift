//
//  AWSClient.swift
//  AWSSDKSwift
//
//  Created by Jonathan McAllister on 2018/10/13.
//
//

import Foundation
import XCTest
@testable import AWSSDKSwiftCore

struct HeaderRequest: AWSShape {
    static var _members: [AWSShapeMember] = [
        AWSShapeMember(label: "Header1", location: .header(locationName: "Header1"), required: true, type: .string),
        AWSShapeMember(label: "Header2", location: .header(locationName: "Header2"), required: true, type: .string),
        AWSShapeMember(label: "Header3", location: .header(locationName: "Header3"), required: true, type: .string),
        AWSShapeMember(label: "Header4", location: .header(locationName: "Header4"), required: true, type: .timestamp)
    ]

    let header1: String
    let header2: String
    let header3: String
    let header4: TimeStamp
}

struct StandardRequest: AWSShape {
    static var _members: [AWSShapeMember] = [
        AWSShapeMember(label: "item1", location: .body(locationName: "item1"), required: true, type: .string),
        AWSShapeMember(label: "item2", location: .body(locationName: "item2"), required: true, type: .integer),
        AWSShapeMember(label: "item3", location: .body(locationName: "item3"), required: true, type: .double),
        AWSShapeMember(label: "item4", location: .body(locationName: "item4"), required: true, type: .timestamp)
    ]

    let item1: String
    let item2: Int
    let item3: Double
    let item4: Date
}

struct PayloadRequest: AWSShape {
    public static let payloadPath: String? = "payload"
    static var _members: [AWSShapeMember] = [
        AWSShapeMember(label: "payload", location: .body(locationName: "payload"), required: true, type: .structure)
    ]

    let payload: StandardRequest
}

struct MixedRequest: AWSShape {
    static var _members: [AWSShapeMember] = [
        AWSShapeMember(label: "item1", location: .header(locationName: "item1"), required: true, type: .string),
        AWSShapeMember(label: "item2", location: .body(locationName: "item2"), required: true, type: .integer),
        AWSShapeMember(label: "item3", location: .body(locationName: "item3"), required: true, type: .double),
        AWSShapeMember(label: "item4", location: .body(locationName: "item4"), required: true, type: .timestamp)
    ]

    let item1: String
    let item2: Int
    let item3: Double
    let item4: Date
}


class PerformanceTests: XCTestCase {
    
    func testHeaderRequest() {
        let client = AWSClient(
            region: .useast1,
            service:"Test",
            serviceProtocol: ServiceProtocol(type: .restxml),
            apiVersion: "1.0",
            eventLoopGroupProvider: .useAWSClientShared
        )
        let date = Date()
        let request = HeaderRequest(header1: "Header1", header2: "Header2", header3: "Header3", header4: TimeStamp(date))
        measure {
            do {
                for _ in 0..<1000 {
                    _ = try client.createAWSRequest(operation: "Test", path: "/", httpMethod: "POST", input: request)
                }
            } catch {
                XCTFail(error.localizedDescription)
            }
        }
    }
    
    func testXMLRequest() {
        let client = AWSClient(
            region: .useast1,
            service:"Test",
            serviceProtocol: ServiceProtocol(type: .restxml),
            apiVersion: "1.0",
            eventLoopGroupProvider: .useAWSClientShared
        )
        let date = Date()
        let request = StandardRequest(item1: "item1", item2: 45, item3: 3.14, item4: date)
        measure {
            do {
                for _ in 0..<1000 {
                    _ = try client.createAWSRequest(operation: "Test", path: "/", httpMethod: "POST", input: request)
                }
            } catch {
                XCTFail(error.localizedDescription)
            }
        }
    }
    
    func testXMLPayloadRequest() {
        let client = AWSClient(
            region: .useast1,
            service:"Test",
            serviceProtocol: ServiceProtocol(type: .restxml),
            apiVersion: "1.0",
            eventLoopGroupProvider: .useAWSClientShared
        )
        let date = Date()
        let request = PayloadRequest(payload: StandardRequest(item1: "item1", item2: 45, item3: 3.14, item4: date))
        measure {
            do {
                for _ in 0..<1000 {
                    _ = try client.createAWSRequest(operation: "Test", path: "/", httpMethod: "POST", input: request)
                }
            } catch {
                XCTFail(error.localizedDescription)
            }
        }
    }
    
    func testJSONRequest() {
        let client = AWSClient(
            region: .useast1,
            service:"Test",
            serviceProtocol: ServiceProtocol(type: .restjson),
            apiVersion: "1.0",
            eventLoopGroupProvider: .useAWSClientShared
        )
        let date = Date()
        let request = StandardRequest(item1: "item1", item2: 45, item3: 3.14, item4: date)
        measure {
            do {
                for _ in 0..<1000 {
                    _ = try client.createAWSRequest(operation: "Test", path: "/", httpMethod: "POST", input: request)
                }
            } catch {
                XCTFail(error.localizedDescription)
            }
        }
    }
    
    func testJSONPayloadRequest() {
        let client = AWSClient(
            region: .useast1,
            service:"Test",
            serviceProtocol: ServiceProtocol(type: .restjson),
            apiVersion: "1.0",
            eventLoopGroupProvider: .useAWSClientShared
        )
        let date = Date()
        let request = PayloadRequest(payload: StandardRequest(item1: "item1", item2: 45, item3: 3.14, item4: date))
        measure {
            do {
                for _ in 0..<1000 {
                    _ = try client.createAWSRequest(operation: "Test", path: "/", httpMethod: "POST", input: request)
                }
            } catch {
                XCTFail(error.localizedDescription)
            }
        }
    }
    
    func testQueryRequest() {
        let client = AWSClient(
            region: .useast1,
            service:"Test",
            serviceProtocol: ServiceProtocol(type: .query),
            apiVersion: "1.0",
            eventLoopGroupProvider: .useAWSClientShared
        )
        let date = Date()
        let request = StandardRequest(item1: "item1", item2: 45, item3: 3.14, item4: date)
        measure {
            do {
                for _ in 0..<1000 {
                    _ = try client.createAWSRequest(operation: "Test", path: "/", httpMethod: "POST", input: request)
                }
            } catch {
                XCTFail(error.localizedDescription)
            }
        }
    }
    
    func testUnsignedRequest() {
        let client = AWSClient(
            accessKeyId: "",
            secretAccessKey: "",
            region: .useast1,
            service:"Test",
            serviceProtocol: ServiceProtocol(type: .json),
            apiVersion: "1.0",
            eventLoopGroupProvider: .useAWSClientShared
        )
        let awsRequest = try! client.createAWSRequest(operation: "Test", path: "/", httpMethod: "GET")
        measure {
            do {
                for _ in 0..<1000 {
                    _ = try client.createNioRequest(awsRequest)
                }
            } catch {
                XCTFail(error.localizedDescription)
            }
        }
    }

    func testSignedURLRequest() {
        let client = AWSClient(
            accessKeyId: "MyAccessKeyId",
            secretAccessKey: "MySecretAccessKey",
            region: .useast1,
            service:"Test",
            serviceProtocol: ServiceProtocol(type: .json),
            apiVersion: "1.0",
            eventLoopGroupProvider: .useAWSClientShared
        )
        let awsRequest = try! client.createAWSRequest(operation: "Test", path: "/", httpMethod: "GET")
        measure {
            do {
                for _ in 0..<1000 {
                    _ = try client.createNioRequest(awsRequest)
                }
            } catch {
                XCTFail(error.localizedDescription)
            }
        }
    }

    func testSignedHeadersRequest() {
        let client = AWSClient(
            accessKeyId: "MyAccessKeyId",
            secretAccessKey: "MySecretAccessKey",
            region: .useast1,
            service:"Test",
            serviceProtocol: ServiceProtocol(type: .json),
            apiVersion: "1.0",
            eventLoopGroupProvider: .useAWSClientShared
        )
        let date = Date()
        let request = StandardRequest(item1: "item1", item2: 45, item3: 3.14, item4: date)
        let awsRequest = try! client.createAWSRequest(operation: "Test", path: "/", httpMethod: "POST", input: request)
        measure {
            do {
                for _ in 0..<1000 {
                    _ = try client.createNioRequest(awsRequest)
                }
            } catch {
                XCTFail(error.localizedDescription)
            }
        }
    }
}
