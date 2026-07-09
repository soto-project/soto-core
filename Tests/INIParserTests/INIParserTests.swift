//===----------------------------------------------------------------------===//
//
// This source file is part of the Soto for AWS open source project
//
// Copyright (c) 2017-2020 the Soto project authors
// Licensed under Apache License v2.0
//
// See LICENSE.txt for license information
// See CONTRIBUTORS.txt for the list of Soto project authors
//
// SPDX-License-Identifier: Apache-2.0
//
//===----------------------------------------------------------------------===//

import Testing

@testable import INIParser

struct INIParserTests {
    @Test func testExample() {
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
                foo = bar
            """

        var ini: INIParser?
        #expect(throws: Never.self) { ini = try INIParser(raw) }

        #expect(ini?.anonymousSection["freeVar1"] ?? "" == "1")
        #expect(ini?.anonymousSection["freeVar2"] ?? "" == "2")
        #expect(ini?.anonymousSection["url"] ?? "" == "http://example.com/results?limit=10")
        #expect(ini?.sections["owner"]?["name"] ?? "" == "Rocky")
        #expect(ini?.sections["owner"]?["organization"] ?? "" == "PerfectlySoft")
        #expect(ini?.sections["database"]?["server"] ?? "" == "192.0.2.42")
        #expect(ini?.sections["database"]?["port"] ?? "" == "143")
        #expect(ini?.sections["database"]?["file"] ?? "" == "\"中文.dat  \' \' \"")
        #expect(ini?.sections["汉化"]?["变量1"] ?? "" == "🇨🇳")
        #expect(ini?.sections["汉化"]?["变量2"] ?? "" == "加拿大。")
        #expect(ini?.sections[" 乱死了 "] != nil)
    }
}
