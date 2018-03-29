import XCTest
@testable import AWSSDKSwiftCoreTests

XCTMain([
     testCase(SerializersTests.allTests),
     testCase(SignersV4Tests.allTests),
     testCase(XML2ParserTests.allTests),
     testCase(DictionaryDecoderTests.allTests),
     testCase(TimeStampTests.allTests),
     testCase(MetaDataServiceTests.allTests)
])
