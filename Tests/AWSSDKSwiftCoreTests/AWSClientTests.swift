//
//  AWSClientTests.swift
//  AWSSDKSwiftCoreTests
//
//  Created by Joe Smith on 2018/06/27.
//

import Foundation
import XCTest
@testable import AWSSDKSwiftCore

class AWSClientTests: XCTestCase {
    static var allTests : [(String, (AWSClientTests) -> () throws -> Void)] {
        return [
            ("testRemoveMembersKeysNoMembers", testRemoveMembersKeysNoMembers),
            ("testRemoveMembersKeys", testRemoveMembersKeys),
            ("testRemoveMembersKeysNested", testRemoveMembersKeysNested),
            ("testJSONMemberParsing", testJSONMemberParsing),
            ("testNestedJSONMemberParsing", testNestedJSONMemberParsing),
        ]
    }

    func testRemoveMembersKeysNoMembers() {
        let expectedDict = ["Result": ["ServerA", "ServerB"], "Metadata": ["Some", "Data"]]
        let client = AWSClient(region: .useast1, service: "iam", serviceProtocol: ServiceProtocol(type: ServiceProtocolType.restxml), apiVersion: "2010-05-08")
        let startDict = ["Result": ["ServerA", "ServerB"], "Metadata": ["Some", "Data"]]
        let resultDict = client.removeMembersKeys(in: startDict)
        if let formattedResult = resultDict as? [String: [String]] {
            XCTAssert(formattedResult == expectedDict, "Improperly parsed \(formattedResult)")
        } else {
            XCTFail("Did not properly parse \(resultDict) into \(expectedDict)")
        }
    }

    func testRemoveMembersKeys() {
        let expectedDict = ["Result": ["ServerA", "ServerB"]]
        let client = AWSClient(region: .useast1, service: "iam", serviceProtocol: ServiceProtocol(type: ServiceProtocolType.restxml), apiVersion: "2010-05-08")
        let startDict = ["Result": ["Member": ["ServerA", "ServerB"]]]
        let resultDict = client.removeMembersKeys(in: startDict)
        if let formattedResult = resultDict as? [String: [String]] {
            XCTAssert(formattedResult == expectedDict, "Improperly parsed \(formattedResult)")
        } else {
            XCTFail("Did not properly parse \(resultDict) into \(expectedDict)")
        }
    }

    func testRemoveMembersKeysNested() {
        let expectedDict = ["Result": [
                "ServerA": ["TagA", "TagB"],
                "ServerB": ["TagC", "TagD"]
        ]]
        let client = AWSClient(region: .useast1, service: "iam", serviceProtocol: ServiceProtocol(type: ServiceProtocolType.restxml), apiVersion: "2010-05-08")
        let startDict = ["Result": ["Member":
            [
                "ServerA": ["Member": ["TagA", "TagB"]],
                "ServerB": ["Member": ["TagC", "TagD"]]
            ]
        ]]
        let resultDict = client.removeMembersKeys(in: startDict)
        if let formattedResult = resultDict as? [String: [String: [String]]] {
            XCTAssert(formattedResult == expectedDict, "Improperly parsed \(formattedResult)")
        } else {
            XCTFail("Did not properly parse \(resultDict) into \(expectedDict)")
        }
    }

    func testJSONMemberParsing() {
        let client = AWSClient(region: .useast1, service: "iam", serviceProtocol: ServiceProtocol(type: ServiceProtocolType.restxml), apiVersion: "2010-05-08")
        do {
            let outputDict = try client.restructureResponse(IAMResponseModel.listServerCertificates, operationName: "ListServerCertificates")

            let response = try DictionaryDecoder().decode(Iam.ListServerCertificatesResponse.self, from: outputDict)
            for certificate in response.serverCertificateMetadataList {
                XCTAssert(certificate.arn.contains(substring: "427300000128"))
            }
        } catch {
            XCTFail("\(error)")
            return
        }
    }

    func testNestedJSONMemberParsing() {
        let client = AWSClient(region: .useast1, service: "autoscaling", serviceProtocol: ServiceProtocol(type: ServiceProtocolType.restxml), apiVersion: "2011-01-01")
        do {
            let outputDict = try client.restructureResponse(AutoscalingResponseModel.describeAutoscalingGroups, operationName: "DescribeAutoScalingGroups")

            let response = try DictionaryDecoder().decode(Autoscaling.AutoScalingGroupsType.self, from: outputDict)
            for group in response.autoScalingGroups {
                XCTAssert(group.autoScalingGroupName == "fake-asg")
            }
        } catch {
            XCTFail("\(error)")
            return
        }
    }
}
