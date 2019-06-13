//
//  QueryEncoderTests.swift
//  AWSSDKSwift
//
//  Created by Adam Fowler 2019/06/12
//
//

import Foundation
import XCTest
@testable import AWSSDKSwiftCore

class QueryEncoderTests: XCTestCase {

    func queryString(dictionary:[String:Any]) -> String? {
        var components = URLComponents()
        components.queryItems = dictionary.map( {URLQueryItem(name:$0.key, value:String(describing: $0.value))} ).sorted(by: { $0.name < $1.name })
        if components.queryItems != nil, let url = components.url {
            return url.query
        }
        return nil
    }
    
    func testQuery(_ value: AWSShape, query: String) {
        let queryDict = AWSShapeEncoder().query(value)
        let query2 = queryString(dictionary: queryDict)
        XCTAssertEqual(query2, query)
    }
    func testSimpleStructureEncode() {
        struct Test : AWSShape {
            let a : String
            let b : Int
        }
        let test = Test(a:"Testing", b:42)
        testQuery(test, query:"A=Testing&B=42")
    }
    
    func testContainingStructureEncode() {
        struct Test : AWSShape {
            let a : Int
            let b : String
        }
        struct Test2 : AWSShape {
            let t : Test
        }
        let test = Test2(t:Test(a:42, b:"Life"))
        testQuery(test, query:"T.A=42&T.B=Life")
    }

    func testEnumEncode() {
        struct Test : AWSShape {
            enum TestEnum : String, Codable {
                case first = "First"
                case second = "Second"
            }
            let a : TestEnum
        }
        let test = Test(a:.second)
        // NB enum names don't change to rawValue (not sure how to fix)
        testQuery(test, query: "A=second")
    }

    func testArrayEncode() {
        struct Test : AWSShape {
            let a : [Int]
        }
        let test = Test(a:[9,8,7,6])
        testQuery(test, query:"A.1=9&A.2=8&A.3=7&A.4=6")
    }
    
    func testArrayOfStructuresEncode() {
        struct Test2 : AWSShape {
            let b : String
        }
        struct Test : AWSShape {
            let a : [Test2]
        }
        let test = Test(a:[Test2(b:"first"), Test2(b:"second")])
        testQuery(test, query:"A.1.B=first&A.2.B=second")
    }
    
    func testDictionaryEncode() {
        struct Test : AWSShape {
            let a : [String:Int]
        }
        let test = Test(a:["first":1])
        testQuery(test, query:"A.entry.1.key=first&A.entry.1.value=1")
    }
    
    func testDictionaryEnumKeyEncode() {
        struct Test2 : AWSShape {
            let b : String
        }
        struct Test : AWSShape {
            enum TestEnum : String, Codable {
                case first = "First"
                case second = "Second"
            }
            let a : [TestEnum:Test2]
        }
        let test = Test(a:[.first:Test2(b:"1st")])
        testQuery(test, query:"A.entry.1.key=first&A.entry.1.value.B=1st")
    }
    
    func testArrayEncodingEncode() {
        struct Test : AWSShape {
            static let _members = [AWSShapeMember(label: "A", location:.body(locationName:"a"), required: true, type: .list, encoding:.list(member:"item"))]
            let a : [Int]
        }
        let test = Test(a:[9,8,7,6])
        testQuery(test, query:"a.item.1=9&a.item.2=8&a.item.3=7&a.item.4=6")
    }
    
    func testDictionaryEncodingEncode() {
        struct Test : AWSShape {
            static let _members = [AWSShapeMember(label: "A", required: true, type: .map, encoding:.map(entry: "item", key: "k", value: "v"))]
            let a : [String:Int]
        }
        let test = Test(a:["first":1])
        testQuery(test, query:"A.item.1.k=first&A.item.1.v=1")
    }
    
    func testDictionaryEncodingEncode2() {
        struct Test : AWSShape {
            static let _members = [AWSShapeMember(label: "A", required: true, type: .map, encoding:.flatMap(key: "name", value: "entry"))]
            let a : [String:Int]
        }
        let test = Test(a:["first":1])
        testQuery(test, query:"A.1.entry=1&A.1.name=first")
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
        ]
    }
}
