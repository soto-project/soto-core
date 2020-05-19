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
@testable import AWSSDKSwiftCore

class FileCredentialProviderTests: XCTestCase {

    func testExpandTildeInFilePath() {
        let expandableFilePath = "~/.aws/credentials"
        let expandedNewPath = StaticCredential.expandTildeInFilePath(expandableFilePath)
        let expandedNSString = NSString(string: expandableFilePath).expandingTildeInPath
        
        XCTAssertEqual(expandedNewPath, expandedNSString)
        
        let unexpandableFilePath = "/.aws/credentials"
        let unexpandedNewPath = StaticCredential.expandTildeInFilePath(unexpandableFilePath)
        let unexpandedNSString = NSString(string: unexpandableFilePath).expandingTildeInPath
        
        XCTAssertEqual(unexpandedNewPath, unexpandedNSString)
        XCTAssertEqual(unexpandedNewPath, unexpandableFilePath)
    }

}
