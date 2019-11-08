import XCTest
@testable import AWSSDKSwiftCoreTests

XCTMain([
    testCase(AWSClientTests.allTests),
    testCase(CredentialTests.allTests),
    testCase(DictionaryEncoderTests.allTests),
    testCase(MetaDataServiceTests.allTests),
    testCase(QueryEncoderTests.allTests),
    testCase(SerializersTests.allTests),
    testCase(TimeStampTests.allTests),
    testCase(ValidationTests.allTests),
    testCase(XMLTests.allTests)
])
