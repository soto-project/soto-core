import XCTest
@testable import AWSSDKSwiftCoreTests

XCTMain([
    testCase(AWSClientTests.allTests),
    testCase(CredentialTests.allTests),
    testCase(DictionaryEncoderTests.allTests),
    testCase(HTTPClientTests.allTests),
    testCase(JSONCoderTests.allTests),
    testCase(MetaDataServiceTests.allTests),
    testCase(PaginateTests.allTests),
    testCase(PerformanceTests.allTests),
    testCase(SignersV4Tests.allTests),
    testCase(TimeStampTests.allTests),
    testCase(ValidationTests.allTests),
    testCase(XMLCoderTests.allTests),
    testCase(XMLTests.allTests)
])
