//
//  QueryEncoderTests.swift
//  AWSSDKSwift
//
//  Created by Adam Fowler 2019/06/12
//
//

import XCTest
@testable import AWSSDKSwiftCore

class QueryEncoderTests: XCTestCase {
    @EnvironmentVariable("ENABLE_TIMING_TESTS", default: true) static var enableTimingTests: Bool

    func queryString(dictionary:[String:Any]) -> String? {
        var components = URLComponents()
        components.queryItems = dictionary.map( {URLQueryItem(name:$0.key, value:String(describing: $0.value))} ).sorted(by: { $0.name < $1.name })
        if components.queryItems != nil, let url = components.url {
            return url.query
        }
        return nil
    }
    
    func testQuery<Input: AWSShape>(_ value: Input, query: String) {
        do {
            let queryDict = try QueryEncoder().encode(value)
            let query2 = queryString(dictionary: queryDict)
            XCTAssertEqual(query2, query)
        } catch {
            XCTFail("\(error)")
        }
    }
    func testSimpleStructureEncode() {
        struct Test : AWSShape {
            let a : String
            let b : Int
            
            private enum CodingKeys: String, CodingKey {
                case a = "A"
                case b = "B"
            }
        }
        let test = Test(a:"Testing", b:42)
        testQuery(test, query:"A=Testing&B=42")
    }
    
    func testContainingStructureEncode() {
        struct Test : AWSShape {
            let a : Int
            let b : String
            
            private enum CodingKeys: String, CodingKey {
                case a = "A"
                case b = "B"
            }
        }
        struct Test2 : AWSShape {
            let t : Test
            
            private enum CodingKeys: String, CodingKey {
                case t = "T"
            }
        }
        let test = Test2(t:Test(a:42, b:"Life"))
        testQuery(test, query:"T.A=42&T.B=Life")
    }

    func testEnumEncode() {
        struct Test : AWSShape {
            enum TestEnum : String, Codable {
                case first = "first"
                case second = "second"
            }
            let a : TestEnum
            
            private enum CodingKeys: String, CodingKey {
                case a = "A"
            }
        }
        let test = Test(a:.second)
        // NB enum names don't change to rawValue (not sure how to fix)
        testQuery(test, query: "A=second")
    }

    func testArrayEncode() {
        struct Test : AWSShape {
            let a : [Int]
            
            private enum CodingKeys: String, CodingKey {
                case a = "A"
            }
        }
        let test = Test(a:[9,8,7,6])
        testQuery(test, query:"A.1=9&A.2=8&A.3=7&A.4=6")
    }
    
    func testArrayOfStructuresEncode() {
        struct Test2 : AWSShape {
            let b : String
            
            private enum CodingKeys: String, CodingKey {
                case b = "B"
            }
        }
        struct Test : AWSShape {
            static let _encoding = [AWSMemberEncoding(label: "A", encoding:.list(member: "m") )]
            let a : [Test2]
            
            private enum CodingKeys: String, CodingKey {
                case a = "A"
            }
        }
        let test = Test(a:[Test2(b:"first"), Test2(b:"second")])
        testQuery(test, query:"A.m.1.B=first&A.m.2.B=second")
    }
    
    func testDictionaryEncode() {
        struct Test : AWSShape {
            static let _encoding = [AWSMemberEncoding(label: "A", encoding:.map(entry: "entry", key: "key", value: "value"))]
            let a : [String:Int]
            
            private enum CodingKeys: String, CodingKey {
                case a = "A"
            }
        }
        let test = Test(a:["first":1])
        testQuery(test, query:"A.entry.1.key=first&A.entry.1.value=1")
    }
    
    func testDictionaryEnumKeyEncode() {
        struct Test2 : AWSShape {
            let b : String
            
            private enum CodingKeys: String, CodingKey {
                case b = "B"
            }
        }
        struct Test : AWSShape {
            static let _encoding = [AWSMemberEncoding(label: "A", encoding:.map(entry: "entry", key: "key", value: "value"))]
            enum TestEnum : String, Codable {
                case first = "first"
                case second = "second"
            }
            let a : [TestEnum:Test2]
            
            private enum CodingKeys: String, CodingKey {
                case a = "A"
            }
        }
        let test = Test(a:[.first:Test2(b:"1st")])
        testQuery(test, query:"A.entry.1.key=first&A.entry.1.value.B=1st")
    }
    
    func testArrayEncodingEncode() {
        struct Test : AWSShape {
            static let _encoding = [AWSMemberEncoding(label: "a", encoding:.list(member:"item"))]
            let a : [Int]
        }
        let test = Test(a:[9,8,7,6])
        testQuery(test, query:"a.item.1=9&a.item.2=8&a.item.3=7&a.item.4=6")
    }
    
    func testDictionaryEncodingEncode() {
        struct Test : AWSShape {
            static let _encoding = [AWSMemberEncoding(label: "A", encoding:.map(entry: "item", key: "k", value: "v"))]
            let a : [String:Int]
            
            private enum CodingKeys: String, CodingKey {
                case a = "A"
            }
        }
        let test = Test(a:["first":1])
        testQuery(test, query:"A.item.1.k=first&A.item.1.v=1")
    }
    
    func testDictionaryEncodingEncode2() {
        struct Test : AWSShape {
            static let _encoding = [AWSMemberEncoding(label: "A", encoding:.flatMap(key: "name", value: "entry"))]
            let a : [String:Int]
            
            private enum CodingKeys: String, CodingKey {
                case a = "A"
            }
        }
        let test = Test(a:["first":1])
        testQuery(test, query:"A.1.entry=1&A.1.name=first")
    }
    
    // array performance in QueryEncoder is slower than expected
    func testQueryArrayPerformance() {
        guard Self.enableTimingTests == true else { return }
        struct Test : AWSShape {
            let a : [Int]
            
            private enum CodingKeys: String, CodingKey {
                case a = "A"
            }
        }
        let test = Test(a:[9,8,7,6,5,4,3])
        measure {
            do {
                for _ in 1...10000 {
                    _ = try QueryEncoder().encode(test)
                }
            } catch {
                XCTFail("\(error)")
            }
        }
    }
    
    func testDataBlobEncode() {
        struct Test : AWSShape {
            let a : Data
        }
        let data = Data("Testing".utf8)
        let test = Test(a:data)
        let result = queryString(dictionary: ["a": data.base64EncodedString()])!
        testQuery(test, query: result)
    }

    static var allTests : [(String, (QueryEncoderTests) -> () throws -> Void)] {
        return [
            ("testSimpleStructureEncode", testSimpleStructureEncode),
            ("testContainingStructureEncode", testContainingStructureEncode),
            ("testEnumEncode", testEnumEncode),
            ("testArrayEncode", testArrayEncode),
            ("testArrayOfStructuresEncode", testArrayOfStructuresEncode),
            ("testDictionaryEncode", testDictionaryEncode),
            ("testDictionaryEnumKeyEncode", testDictionaryEnumKeyEncode),
            ("testArrayEncodingEncode", testArrayEncodingEncode),
            ("testDictionaryEncodingEncode", testDictionaryEncodingEncode),
            ("testDictionaryEncodingEncode2", testDictionaryEncodingEncode2),
            ("testDataBlobEncode", testDataBlobEncode)
        ]
    }
}
