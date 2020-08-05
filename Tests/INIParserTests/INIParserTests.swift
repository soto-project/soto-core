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

@testable import INIParser
import XCTest

class INIParserTests: XCTestCase {
    func testExample() {
        let raw = """
        ; last modified 1 April 2017 by Rockford Wei
        ## This is another comment
          freeVar1 = 1
          freeVar2 = 2;
          url = http://example.com/results?limit=10
          [owner]
          name =  Rocky
          organization = PerfectlySoft
          ;
          [database]
              server = 192.0.2.42 ; use IP address in case network name resolution is not working
              port = 143
              file = \"中文.dat  ' ' \"
          [汉化]
          变量1 = 🇨🇳 ;使用utf8
          变量2 = 加拿大。
          [ 乱死了 ]
        """

        var ini: INIParser?
        XCTAssertNoThrow(ini = try INIParser(raw))

        XCTAssertEqual(ini?.anonymousSection["freeVar1"] ?? "", "1")
        XCTAssertEqual(ini?.anonymousSection["freeVar2"] ?? "", "2")
        XCTAssertEqual(ini?.anonymousSection["url"] ?? "", "http://example.com/results?limit=10")
        XCTAssertEqual(ini?.sections["owner"]?["name"] ?? "", "Rocky")
        XCTAssertEqual(ini?.sections["owner"]?["organization"] ?? "", "PerfectlySoft")
        XCTAssertEqual(ini?.sections["database"]?["server"] ?? "", "192.0.2.42")
        XCTAssertEqual(ini?.sections["database"]?["port"] ?? "", "143")
        XCTAssertEqual(ini?.sections["database"]?["file"] ?? "", "\"中文.dat  \' \' \"")
        XCTAssertEqual(ini?.sections["汉化"]?["变量1"] ?? "", "🇨🇳")
        XCTAssertEqual(ini?.sections["汉化"]?["变量2"] ?? "", "加拿大。")
    }

    static var allTests = [
        ("testExample", testExample),
    ]
}
