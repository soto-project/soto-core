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
@testable import AWSSDKSwiftCore

class MetaDataServiceTests: XCTestCase {

    func testInstanceMetaDataService() {
        let body: [String: String] = ["Code" : "Success",
                                      "LastUpdated" : "2018-01-05T05:25:41Z",
                                      "Type" : "AWS-HMAC",
                                      "AccessKeyId" : "XYZABCJOXYK7TPHCHTRKAA",
                                      "SecretAccessKey" : "X+9PUEvV/xS2a7xQTg",
                                      "Token" : "XYZ123dzENH//////////",
                                      "Expiration" : "2017-12-30T13:22:39Z"]

        do {
            let encodedData = try JSONEncoder().encodeAsByteBuffer(body, allocator: ByteBufferAllocator())
            let instanceMetaData = InstanceMetaDataServiceProvider()
            let credential = instanceMetaData.decodeCredential(encodedData)

            XCTAssertNotNil(credential)
            XCTAssertEqual(credential?.accessKeyId, "XYZABCJOXYK7TPHCHTRKAA")
            XCTAssertEqual(credential?.secretAccessKey, "X+9PUEvV/xS2a7xQTg")
            XCTAssertEqual(credential?.sessionToken, "XYZ123dzENH//////////")
        } catch {
            XCTFail(error.localizedDescription)
        }
    }

    func testInstanceMetaDataServiceFail() {
        // removed "Code" entry
        let body: [String: String] = ["LastUpdated" : "2018-01-05T05:25:41Z",
                                      "Type" : "AWS-HMAC",
                                      "AccessKeyId" : "XYZABCJOXYK7TPHCHTRKAA",
                                      "SecretAccessKey" : "X+9PUEvV/xS2a7xQTg",
                                      "Token" : "XYZ123dzENH//////////",
                                      "Expiration" : "2017-12-30T13:22:39Z"]

        do {
            let encodedData = try JSONEncoder().encodeAsByteBuffer(body, allocator: ByteBufferAllocator())
            let instanceMetaData = InstanceMetaDataServiceProvider()
            let credential = instanceMetaData.decodeCredential(encodedData)
            XCTAssertNil(credential)
        } catch {
            XCTFail(error.localizedDescription)
        }
    }

    // Disabling cannot guarantee that 169.254.169.254 is not a valid IP on another network
    func testMetaDataGetCredential() {
        if Environment["TEST_EC2_METADATA"] != nil {
            do {
                let httpClient = HTTPClient(eventLoopGroupProvider: .createNew)
                _ = try MetaDataService.getCredential(httpClient: httpClient, on: httpClient.eventLoopGroup.next()).wait()
            } catch {
                XCTFail("Unexpected error: \(error)")
            }
        }
    }

}
