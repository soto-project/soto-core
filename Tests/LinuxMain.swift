import XCTest
@testable import AWSSDKSwiftCoreTests

XCTMain([
    testCase(AWSClientTests.allTests),
    testCase(CredentialTests.allTests),
    testCase(DictionaryEncoderTests.allTests),
    testCase(HTTPClientTests.allTests),
    testCase(MetaDataServiceTests.allTests),
    testCase(SerializersTests.allTests),
    testCase(SignersV4Tests.allTests),
    testCase(TimeStampTests.allTests),
    testCase(XMLTests.allTests)
])
