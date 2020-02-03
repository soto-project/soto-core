import XCTest
@testable import AWSSDKSwiftCoreTests
@testable import AWSSignerTests

XCTMain([
    testCase(AsyncHTTPClientTests.allTests),
    testCase(AWSClientTests.allTests),
    testCase(CredentialTests.allTests),
    testCase(DictionaryEncoderTests.allTests),
    testCase(JSONCoderTests.allTests),
    testCase(MetaDataServiceTests.allTests),
    testCase(PaginateTests.allTests),
    testCase(PerformanceTests.allTests),
    testCase(QueryEncoderTests.allTests),
    testCase(SerializersTests.allTests),
    testCase(TimeStampTests.allTests),
    testCase(ValidationTests.allTests),
    testCase(XMLCoderTests.allTests),
    testCase(XMLTests.allTests),
    testCase(AWSSignerTests.allTests)
])
