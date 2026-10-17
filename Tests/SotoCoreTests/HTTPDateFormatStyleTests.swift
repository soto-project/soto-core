//===----------------------------------------------------------------------===//
//
// This source file is part of the Soto for AWS open source project
//
// Copyright (c) 2021-2022 the Soto project authors
// Licensed under Apache License v2.0
//
// See LICENSE.txt for license information
// See CONTRIBUTORS.txt for the list of Soto project authors
//
// SPDX-License-Identifier: Apache-2.0
//
//===----------------------------------------------------------------------===//

import Foundation
import SotoCore
import Testing

struct HTTPDateFormatStyleTests {
    @Test(arguments: [
        (Date(timeIntervalSince1970: 0), "Thu, 01 Jan 1970 00:00:00 GMT"),
        (Date(timeIntervalSince1970: 100000), "Fri, 02 Jan 1970 03:46:40 GMT"),
        (Date(timeIntervalSince1970: 1_000_000), "Mon, 12 Jan 1970 13:46:40 GMT"),
        (Date(timeIntervalSince1970: 10_000_000), "Sun, 26 Apr 1970 17:46:40 GMT"),
        (Date(timeIntervalSince1970: 100_000_000), "Sat, 03 Mar 1973 09:46:40 GMT"),
        (Date(timeIntervalSince1970: 1_000_000_000), "Sun, 09 Sep 2001 01:46:40 GMT"),
    ])
    func format(date: Date, formatted: String) {
        #expect(date.httpHeader == formatted)
    }

    @Test(arguments: [
        ("Thu, 01 Jan 1970 00:00:00 GMT", Date(timeIntervalSince1970: 0)),
        ("Fri, 02 Jan 1970 03:46:40 GMT", Date(timeIntervalSince1970: 100000)),
        ("Mon, 12 Jan 1970 13:46:40 GMT", Date(timeIntervalSince1970: 1_000_000)),
        ("Sun, 26 Apr 1970 17:46:40 GMT", Date(timeIntervalSince1970: 10_000_000)),
        ("Sat, 03 Mar 1973 09:46:40 GMT", Date(timeIntervalSince1970: 100_000_000)),
        ("Sun, 09 Sep 2001 01:46:40 GMT", Date(timeIntervalSince1970: 1_000_000_000)),
    ])
    func parse(string: String, date: Date) {
        #expect(Date(httpHeader: string) == date)
    }

    @Test(arguments: [
        "Thu, 02 Jan 1970 00:00:00 GMT",  // wrong day of week
        "Thu, 30 Feb 1970 00:00:00 GMT",  // invalid day of month
        "Ikl, 30 Mar 1970 00:00:00 GMT",  // invalid week day name
        "Mon, 30 Zxt 1970 00:00:00 GMT",  // invalid month name
    ])
    func parseInvalidDate(string: String) {
        let date = Date(httpHeader: string)
        if let date {
            print(date.httpHeader)
        }
        #expect(Date(httpHeader: string) == nil)
    }
}
