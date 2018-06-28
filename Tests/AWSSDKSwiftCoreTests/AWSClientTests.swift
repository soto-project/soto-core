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
            ("testJSONMemberParsing", testJSONMemberParsing),
            ("testNestedJSONMemberParsing", testNestedJSONMemberParsing),
        ]
    }

    func testJSONMemberParsing() {
        let client = AWSClient(region: .useast1, service: "iam", serviceProtocol: ServiceProtocol(type: ServiceProtocolType.restxml), apiVersion: "2010-05-08")
        do {
            let outputDict = try client.restructureResponse(IAMResponseModel.listServerCertificates, operationName: "ListServerCertificates")

            /*let response = try DictionaryDecoder().decode(Iam.ListServerCertificatesResponse.self, from: outputDict)
            for certificate in response.serverCertificateMetadataList {
                XCTAssert(certificate.arn.contains(substring: "427300000128"))
            }*/
        } catch {
            XCTFail("\(error)")
            return
        }
    }

    func testNestedJSONMemberParsing() {
        let client = AWSClient(region: .useast1, service: "autoscaling", serviceProtocol: ServiceProtocol(type: ServiceProtocolType.restxml), apiVersion: "2011-01-01")
        do {
            /*let outputDict = try client.restructureResponse(AutoscalingResponseModel.describeAutoscalingGroups, operationName: "DescribeAutoscalingGroups")

            let response = try DictionaryDecoder().decode(Autoscaling.AutoScalingGroupsType.self, from: outputDict)
            for group in response.autoScalingGroups {
                XCTAssert(group.autoScalingGroupName == "fake-asg")
            }*/
        } catch {
            XCTFail("\(error)")
            return
        }
    }
}
