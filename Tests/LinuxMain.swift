import XCTest
@testable import AWSSDKSwiftCoreTests

XCTMain([
     testCase(SerializableTests.allTests),
     testCase(SignersV4TestsTests.allTests),
     testCase(XML2ParserTests.allTests)
])
