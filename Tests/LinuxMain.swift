import XCTest
@testable import AWSSDKSwiftCoreTests

XCTMain([
     testCase(SerializersTests.allTests),
     testCase(SignersV4TestsTests.allTests),
     testCase(XML2ParserTests.allTests),
     testCase(DictionaryDecoderTests.allTests),
     testCase(TimeStampTests.allTests)
])
