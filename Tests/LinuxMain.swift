import XCTest
@testable import AWSSDKSwiftCoreTests

XCTMain([
     testCase(AWSClientTests.allTests),
     testCase(DictionaryDecoderTests.allTests),
     testCase(MetaDataServiceTests.allTests),
     testCase(SerializersTests.allTests),
     testCase(SignersV4Tests.allTests),
     testCase(TimeStampTests.allTests),
     testCase(XML2ParserTests.allTests),
])
