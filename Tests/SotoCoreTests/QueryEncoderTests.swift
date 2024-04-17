//===----------------------------------------------------------------------===//
//
// This source file is part of the Soto for AWS open source project
//
// Copyright (c) 2017-2022 the Soto project authors
// Licensed under Apache License v2.0
//
// See LICENSE.txt for license information
// See CONTRIBUTORS.txt for the list of Soto project authors
//
// SPDX-License-Identifier: Apache-2.0
//
//===----------------------------------------------------------------------===//

@testable import SotoCore
import SotoTestUtils
import XCTest

class QueryEncoderTests: XCTestCase {
    @EnvironmentVariable("ENABLE_TIMING_TESTS", default: true) static var enableTimingTests: Bool

    func testQuery(_ value: some Encodable, query: String) {
        do {
            let query2 = try QueryEncoder().encode(value)
            XCTAssertEqual(query2, query)
        } catch {
            XCTFail("\(error)")
        }
    }

    func testSimpleStructureEncode() {
        struct Test: AWSEncodableShape {
            let a: String
            let b: Int

            private enum CodingKeys: String, CodingKey {
                case a = "A"
                case b = "B"
            }
        }
        let test = Test(a: "Testing", b: 42)
        self.testQuery(test, query: "A=Testing&B=42")
    }

    func testContainingStructureEncode() {
        struct Test: AWSEncodableShape {
            let a: Int
            let b: String

            private enum CodingKeys: String, CodingKey {
                case a = "A"
                case b = "B"
            }
        }
        struct Test2: AWSEncodableShape {
            let t: Test

            private enum CodingKeys: String, CodingKey {
                case t = "T"
            }
        }
        let test = Test2(t: Test(a: 42, b: "Life"))
        self.testQuery(test, query: "T.A=42&T.B=Life")
    }

    func testEnumEncode() {
        struct Test: AWSEncodableShape {
            enum TestEnum: String, Codable {
                case first
                case second
            }

            let a: TestEnum

            private enum CodingKeys: String, CodingKey {
                case a = "A"
            }
        }
        let test = Test(a: .second)
        // NB enum names don't change to rawValue (not sure how to fix)
        self.testQuery(test, query: "A=second")
    }

    func testArrayEncode() {
        struct Test: AWSEncodableShape {
            let a: [Int]

            private enum CodingKeys: String, CodingKey {
                case a = "A"
            }
        }
        let test = Test(a: [9, 8, 7, 6])
        self.testQuery(test, query: "A.1=9&A.2=8&A.3=7&A.4=6")
    }

    func testArrayOfStructuresEncode() {
        struct ArrayM: ArrayCoderProperties { static let member = "m" }
        struct Test2: AWSEncodableShape {
            let b: String

            private enum CodingKeys: String, CodingKey {
                case b = "B"
            }
        }
        struct Test: AWSEncodableShape {
            @CustomCoding<ArrayCoder<ArrayM, Test2>> var a: [Test2]

            private enum CodingKeys: String, CodingKey {
                case a = "A"
            }
        }
        let test = Test(a: [Test2(b: "first"), Test2(b: "second")])
        self.testQuery(test, query: "A.m.1.B=first&A.m.2.B=second")
    }

    func testDictionaryEncode() {
        struct Test: AWSEncodableShape {
            @CustomCoding<StandardDictionaryCoder> var a: [String: Int]

            private enum CodingKeys: String, CodingKey {
                case a = "A"
            }
        }
        let test = Test(a: ["first": 1])
        self.testQuery(test, query: "A.entry.1.key=first&A.entry.1.value=1")
    }

    func testDictionaryEnumKeyEncode() {
        struct Test2: AWSEncodableShape {
            let b: String

            private enum CodingKeys: String, CodingKey {
                case b = "B"
            }
        }
        struct Test: AWSEncodableShape {
            enum TestEnum: String, Codable {
                case first
                case second
            }

            @CustomCoding<StandardDictionaryCoder> var a: [TestEnum: Test2]

            private enum CodingKeys: String, CodingKey {
                case a = "A"
            }
        }
        let test = Test(a: [.first: Test2(b: "1st")])
        self.testQuery(test, query: "A.entry.1.key=first&A.entry.1.value.B=1st")
    }

    func testArrayEncodingEncode() {
        struct ArrayItem: ArrayCoderProperties { static let member = "item" }
        struct Test: AWSEncodableShape {
            @CustomCoding<ArrayCoder<ArrayItem, Int>> var a: [Int]
        }
        let test = Test(a: [9, 8, 7, 6])
        self.testQuery(test, query: "a.item.1=9&a.item.2=8&a.item.3=7&a.item.4=6")
    }

    func testDictionaryEncodingEncode() {
        struct DictionaryItemKV: DictionaryCoderProperties { static let entry: String? = "item"; static let key = "k"; static let value = "v" }
        struct Test: AWSEncodableShape {
            @CustomCoding<DictionaryCoder<DictionaryItemKV, String, Int>> var a: [String: Int]

            private enum CodingKeys: String, CodingKey {
                case a = "A"
            }
        }
        let test = Test(a: ["first": 1])
        self.testQuery(test, query: "A.item.1.k=first&A.item.1.v=1")
    }

    func testDictionaryEncodingEncode2() {
        struct DictionaryNameEntry: DictionaryCoderProperties {
            static let entry: String? = nil; static let key = "name"; static let value = "entry"
        }
        struct Test: AWSEncodableShape {
            @CustomCoding<DictionaryCoder<DictionaryNameEntry, String, Int>> var a: [String: Int]

            private enum CodingKeys: String, CodingKey {
                case a = "A"
            }
        }
        let test = Test(a: ["first": 1])
        self.testQuery(test, query: "A.1.entry=1&A.1.name=first")
    }

    func testBase64DataEncode() {
        struct Test: AWSEncodableShape {
            let a: AWSBase64Data
        }
        let data = Data("Testing".utf8)
        let test = Test(a: .data(data))
        self.testQuery(test, query: "a=VGVzdGluZw%3D%3D")
    }

    func testEC2Encode() {
        struct Test2: AWSEncodableShape {
            let data: String
        }
        struct Test: AWSEncodableShape {
            let object: Test2
        }
        do {
            let value = Test(object: Test2(data: "Hello"))
            var queryEncoder = QueryEncoder()
            queryEncoder.ec2 = true
            let query = try queryEncoder.encode(value)

            XCTAssertEqual(query, "Object.Data=Hello")
        } catch {
            XCTFail("\(error)")
        }
    }
}
