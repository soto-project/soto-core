//
//  TimeStampTests.swift
//  AWSSDKSwiftCoreTests
//
//  Created by Yuki Takei on 2017/10/09.
//

import Foundation
import XCTest
@testable import AWSSDKSwiftCore

class TimeStampTests: XCTestCase {
    
    struct A: Codable {
        let date: TimeStamp
    }
    
    func testInitializer() {
        do {
            let now = Date().timeIntervalSince1970
            let ts = TimeStamp(Double(now))
            XCTAssertEqual(now, ts.doubleValue)
        }
        
        do {
            let now = Date()
            let ts = TimeStamp(now)
            XCTAssertEqual(now, ts.dateValue)
        }
        
        do {
            let now = "2017-01-01 00:00:00"
            let ts = TimeStamp(now)
            XCTAssertEqual(now, ts.stringValue)
        }
        
        do {
            let now = Int(Date().timeIntervalSince1970)
            let ts = TimeStamp(now)
            XCTAssertEqual(now, ts.intValue)
        }
    }
    
    func testDecodeFromJSON() {
        do {
            let json = "{\"date\": \"2017-01-01 00:00:00\"}"
            let a = try JSONDecoder().decode(A.self, from: json.data)
            XCTAssertEqual(a.date.stringValue, "2017-01-01 00:00:00")
        } catch {
            XCTFail("\(error)")
        }
        
        do {
            let now = Date().timeIntervalSince1970
            let json = "{\"date\": \(now)}"
            _ = try JSONDecoder().decode(A.self, from: json.data)
        } catch {
            XCTFail("\(error)")
        }
        
        do {
            let now = Int(Date().timeIntervalSince1970)
            let json = "{\"date\": \(now)}"
            let a = try JSONDecoder().decode(A.self, from: json.data)
            XCTAssertEqual(a.date.intValue, now)
        } catch {
            XCTFail("\(error)")
        }
    }
    
    func testEncodeToJSON() {
        do {
            let a = A(date: "2017-01-01 00:00:00")
            let data = try JSONEncoder().encode(a)
            let jsonString = String(data: data, encoding: .utf8)
            XCTAssertEqual(jsonString, "{\"date\":\"2017-01-01 00:00:00\"}")
        } catch {
            XCTFail("\(error)")
        }
        
        do {
            let now = Date().timeIntervalSince1970
            let a = A(date: TimeStamp(now))
            let data = try JSONEncoder().encode(a)
            let jsonString = String(data: data, encoding: .utf8)
            XCTAssertNotNil(jsonString)
        } catch {
            XCTFail("\(error)")
        }
        
        do {
            let now = Int(Date().timeIntervalSince1970)
            let a = A(date: TimeStamp(now))
            let data = try JSONEncoder().encode(a)
            let jsonString = String(data: data, encoding: .utf8)
            XCTAssertEqual(jsonString, "{\"date\":\(now)}")
        } catch {
            XCTFail("\(error)")
        }
        
        do {
            let now = Date()
            let a = A(date: TimeStamp(now))
            let data = try JSONEncoder().encode(a)
            let jsonString = String(data: data, encoding: .utf8)
            XCTAssertEqual(jsonString, "{\"date\":\"\(now)\"}")
        } catch {
            XCTFail("\(error)")
        }
    }
    
    static var allTests : [(String, (TimeStampTests) -> () throws -> Void)] {
        return [
            ("testInitializer", testInitializer),
            ("testDecodeFromJSON", testDecodeFromJSON),
            ("testEncodeToJSON", testEncodeToJSON),
        ]
    }
}

