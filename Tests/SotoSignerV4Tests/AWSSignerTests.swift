//===----------------------------------------------------------------------===//
//
// This source file is part of the Soto for AWS open source project
//
// Copyright (c) 2017-2020 the Soto project authors
// Licensed under Apache License v2.0
//
// See LICENSE.txt for license information
// See CONTRIBUTORS.txt for the list of Soto project authors
//
// SPDX-License-Identifier: Apache-2.0
//
//===----------------------------------------------------------------------===//

import Crypto
import Foundation
import HTTPTypes
@_spi(SotoInternal) import SotoSignerV4
import Testing

@testable import SotoSignerV4

@propertyWrapper struct EnvironmentVariable<Value: LosslessStringConvertible> {
    var defaultValue: Value
    var variableName: String

    public init(_ variableName: String, default: Value) {
        self.defaultValue = `default`
        self.variableName = variableName
    }

    public var wrappedValue: Value {
        guard let value = ProcessInfo.processInfo.environment[variableName] else { return self.defaultValue }
        return Value(value) ?? self.defaultValue
    }
}

final class AWSSignerTests {
    let credentials: Credential = Credential(accessKeyId: "MYACCESSKEY", secretAccessKey: "MYSECRETACCESSKEY")
    let credentialsWithSessionKey: Credential = Credential(
        accessKeyId: "MYACCESSKEY",
        secretAccessKey: "MYSECRETACCESSKEY",
        sessionToken: "MYSESSIONTOKEN"
    )
    let awsSampleCredentials: Credential = Credential(
        accessKeyId: "AKIAIOSFODNN7EXAMPLE",
        secretAccessKey: "wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY"
    )

    @Test func testSignGetHeaders() {
        let signer = AWSSigner(credentials: credentials, name: "glacier", region: "us-east-1")
        var request = HTTPRequest(
            method: .get,
            url: URL(string: "https://glacier.us-east-1.amazonaws.com/-/vaults")!,
            headerFields: [.init("x-amz-glacier-version")!: "2012-06-01"]
        )
        signer.signHeaders(
            request: &request,
            date: Date(timeIntervalSinceReferenceDate: 2_000_000)
        )
        #expect(
            request.headerFields[.authorization]
                == "AWS4-HMAC-SHA256 Credential=MYACCESSKEY/20010124/us-east-1/glacier/aws4_request, SignedHeaders=host;x-amz-content-sha256;x-amz-date;x-amz-glacier-version, Signature=acfa9b03fca6b098d7b88bfd9bbdb4687f5b34e944a9c6ed9f4814c1b0b06d62"
        )
    }

    @Test func testSignWithSlashAtEndOfPath() {
        let signer = AWSSigner(credentials: credentials, name: "sns", region: "eu-central-1")
        var request = HTTPRequest(method: .get, url: URL(string: "https://sns.eu-central-1.amazonaws.com/topics/")!)
        signer.signHeaders(
            request: &request,
            date: Date(timeIntervalSinceReferenceDate: 2_000_000)
        )
        #expect(
            request.headerFields[.authorization]
                == "AWS4-HMAC-SHA256 Credential=MYACCESSKEY/20010124/eu-central-1/sns/aws4_request, SignedHeaders=host;x-amz-content-sha256;x-amz-date, Signature=9c04ae96a2ce8addfa7ce933bf7ddda342f42476bd8cef057d1d25f09fb059c1"
        )
    }

    @available(macOS 26, iOS 26, tvOS 26, watchOS 26, visionOS 26, *)
    @Test func testSignPutHeaders() {
        let signer = AWSSigner(credentials: credentials, name: "sns", region: "eu-west-1")
        var request = HTTPRequest(
            method: .post,
            url: URL(string: "https://sns.eu-west-1.amazonaws.com/")!,
            headerFields: [.contentType: "application/x-www-form-urlencoded; charset=utf-8"]
        )
        signer.signHeaders(
            request: &request,
            body: "Action=ListTopics&Version=2010-03-31".utf8.span.bytes,
            date: Date(timeIntervalSinceReferenceDate: 200)
        )
        #expect(
            request.headerFields[.authorization]
                == "AWS4-HMAC-SHA256 Credential=MYACCESSKEY/20010101/eu-west-1/sns/aws4_request, SignedHeaders=content-type;host;x-amz-content-sha256;x-amz-date, Signature=1d29943055a8ad094239e8de06082100f2426ebbb2c6a5bbcbb04c63e6a3f274"
        )
    }

    @Test func testHeadersWithWhitespace() {
        let signer = AWSSigner(credentials: credentials, name: "sns", region: "eu-west-1")
        var request = HTTPRequest(
            method: .get,
            url: URL(string: "https://sns.eu-west-1.amazonaws.com/")!,
            headerFields: [.init("Header1")!: "value1", .init("Header2")!: "value2", .init("Header3")!: "value3"]
        )
        signer.signHeaders(
            request: &request,
            date: Date(timeIntervalSinceReferenceDate: 200)
        )
        var requestWithWhitespace = HTTPRequest(
            method: .get,
            url: URL(string: "https://sns.eu-west-1.amazonaws.com/")!,
            headerFields: [.init("Header1")!: " value1", .init("Header2")!: "value2 ", .init("Header3")!: " value3"]
        )
        signer.signHeaders(
            request: &requestWithWhitespace,
            date: Date(timeIntervalSinceReferenceDate: 200)
        )
        #expect(
            request.headerFields[.authorization] == requestWithWhitespace.headerFields[.authorization]
        )
    }

    @Test func testSignS3GetURL() {
        let signer = AWSSigner(credentials: credentials, name: "s3", region: "us-east-1")
        let request = HTTPRequest(method: .get, url: URL(string: "https://s3.us-east-1.amazonaws.com/")!)
        let url = signer.signURL(
            request: request,
            expires: .seconds(24 * 60 * 60),
            date: Date(timeIntervalSinceReferenceDate: 100_000)
        )
        #expect(
            url?.absoluteString
                == "https://s3.us-east-1.amazonaws.com/?X-Amz-Algorithm=AWS4-HMAC-SHA256&X-Amz-Credential=MYACCESSKEY%2F20010102%2Fus-east-1%2Fs3%2Faws4_request&X-Amz-Date=20010102T034640Z&X-Amz-Expires=86400&X-Amz-SignedHeaders=host&X-Amz-Signature=27957103c8bfdff3560372b1d85976ed29c944f34295eca2d4fdac7fc02c375a"
        )
    }

    @Test func testSignS3GetWithQueryURL() {
        let signer = AWSSigner(credentials: credentials, name: "s3", region: "us-east-1")
        let request = HTTPRequest(method: .get, url: URL(string: "https://s3.us-east-1.amazonaws.com/testFile?versionId=1")!)
        let url = signer.signURL(
            request: request,
            expires: .seconds(24 * 60 * 60),
            date: Date(timeIntervalSinceReferenceDate: 100_000)
        )
        #expect(
            url?.absoluteString
                == "https://s3.us-east-1.amazonaws.com/testFile?X-Amz-Algorithm=AWS4-HMAC-SHA256&X-Amz-Credential=MYACCESSKEY%2F20010102%2Fus-east-1%2Fs3%2Faws4_request&X-Amz-Date=20010102T034640Z&X-Amz-Expires=86400&X-Amz-SignedHeaders=host&versionId=1&X-Amz-Signature=22678dbcdbbc468c306757c8abd021e093e588e4eba7d0d0da9b92717bbcc1b0"
        )
    }

    @Test func testSignS3PutURL() {
        let signer = AWSSigner(credentials: credentialsWithSessionKey, name: "s3", region: "eu-west-1")
        let request = HTTPRequest(method: .put, url: URL(string: "https://test-bucket.s3.amazonaws.com/test-put.txt")!)
        let url = signer.signURL(
            request: request,
            expires: .seconds(24 * 60 * 60),
            date: Date(timeIntervalSinceReferenceDate: 100_000)
        )
        #expect(
            url?.absoluteString
                == "https://test-bucket.s3.amazonaws.com/test-put.txt?X-Amz-Algorithm=AWS4-HMAC-SHA256&X-Amz-Credential=MYACCESSKEY%2F20010102%2Feu-west-1%2Fs3%2Faws4_request&X-Amz-Date=20010102T034640Z&X-Amz-Expires=86400&X-Amz-Security-Token=MYSESSIONTOKEN&X-Amz-SignedHeaders=host&X-Amz-Signature=969dfbc450089f34f5b430611b18def1701c72c9e7e1608142051a898094227e"
        )
    }

    @Test func testSignOmitSessionToken() {
        let signer = AWSSigner(credentials: credentialsWithSessionKey, name: "glacier", region: "us-east-1")
        var request = HTTPRequest(
            method: .get,
            url: URL(string: "https://glacier.us-east-1.amazonaws.com/-/vaults")!,
            headerFields: [.init("x-amz-glacier-version")!: "2012-06-01"]
        )
        signer.signHeaders(
            request: &request,
            omitSecurityToken: true,
            date: Date(timeIntervalSinceReferenceDate: 2_000_000)
        )
        #expect(
            request.headerFields[.authorization]
                == "AWS4-HMAC-SHA256 Credential=MYACCESSKEY/20010124/us-east-1/glacier/aws4_request, SignedHeaders=host;x-amz-content-sha256;x-amz-date;x-amz-glacier-version, Signature=acfa9b03fca6b098d7b88bfd9bbdb4687f5b34e944a9c6ed9f4814c1b0b06d62"
        )
    }

    @Test func testProcessURL() {
        let signer = AWSSigner(credentials: credentials, name: "s3", region: "eu-west-1")
        let url = URL(string: "https://test.s3.amazonaws.com?test2=true&test1=false")!
        #expect(signer.processURL(url: url) == URL(string: "https://test.s3.amazonaws.com?test1=false&test2=true"))
        let url2 = URL(string: "https://test.s3.amazonaws.com?test=hello+goodbye")!
        #expect(signer.processURL(url: url2) == URL(string: "https://test.s3.amazonaws.com?test=hello%2Bgoodbye"))
        let url3 = URL(string: "https://test.s3.amazonaws.com?test=hello%20goodbye")!
        #expect(signer.processURL(url: url3) == URL(string: "https://test.s3.amazonaws.com?test=hello%20goodbye"))
        let url4 = URL(string: "https://test.s3.amazonaws.com?test=hello&item=orange&item=apple")!
        #expect(signer.processURL(url: url4) == URL(string: "https://test.s3.amazonaws.com?item=apple&item=orange&test=hello"))
        let url5 = URL(string: "https://test.s3.amazonaws.com?item&item=apple")!
        #expect(signer.processURL(url: url5) == URL(string: "https://test.s3.amazonaws.com?item=&item=apple"))
    }

    @Test func testSignS3PutWithHeaderURL() {
        let signer = AWSSigner(credentials: credentialsWithSessionKey, name: "s3", region: "eu-west-1")
        let request = HTTPRequest(
            method: .put,
            url: URL(string: "https://test-bucket.s3.amazonaws.com/test-put.txt")!,
            headerFields: [.init("x-amz-acl")!: "public-read"]
        )
        let url = signer.signURL(
            request: request,
            expires: .seconds(24 * 60 * 60),
            date: Date(timeIntervalSinceReferenceDate: 100_000)
        )
        #expect(
            url?.absoluteString
                == "https://test-bucket.s3.amazonaws.com/test-put.txt?X-Amz-Algorithm=AWS4-HMAC-SHA256&X-Amz-Credential=MYACCESSKEY%2F20010102%2Feu-west-1%2Fs3%2Faws4_request&X-Amz-Date=20010102T034640Z&X-Amz-Expires=86400&X-Amz-Security-Token=MYSESSIONTOKEN&X-Amz-SignedHeaders=host%3Bx-amz-acl&X-Amz-Signature=a849c034af312e8424b3b0dd425e3e21ce7a61641f4b6a84c203b115447309c8"
        )
    }

    @Test func testCanonicalRequest() throws {
        let url = URL(string: "https://test.com/test?hello=true&item=apple")!
        let signer = AWSSigner(credentials: credentials, name: "sns", region: "eu-west-1")
        let body = Data("{}".utf8)
        let signingData = AWSSigner.SigningData(
            url: url,
            request: HTTPRequest(method: .post, url: url, headerFields: [.contentType: "application/json"]),
            hashedPayload: SHA256.hash(data: body).hexDigest(),
            date: Date(timeIntervalSince1970: 234_873).formatted(.iso8601),
            signer: signer
        )
        let request = signer.canonicalRequest(signingData: signingData)
        let expectedRequest = """
            POST
            /test
            hello=true&item=apple
            content-type:application/json
            host:test.com

            content-type;host
            44136fa355b3678a1146ad16f7e8649e94fb4fc21fe77e8310c060f61caaff8a
            """
        #expect(request == expectedRequest)
    }

    @Test func testCanonicalRequestSequentialSpace() throws {
        let url = URL(string: "https://test.com/test")!
        let signer = AWSSigner(credentials: credentials, name: "sns", region: "eu-west-1")
        let body = Data("{}".utf8)
        let signingData = AWSSigner.SigningData(
            url: url,
            request: HTTPRequest(method: .post, url: url, headerFields: [.contentType: "application/json", .init("header")!: "my  header"]),
            hashedPayload: SHA256.hash(data: body).hexDigest(),
            date: Date(timeIntervalSince1970: 234_873).formatted(.iso8601),
            signer: signer
        )
        let request = signer.canonicalRequest(signingData: signingData)
        let expectedRequest = """
            POST
            /test

            content-type:application/json
            header:my header
            host:test.com

            content-type;header;host
            44136fa355b3678a1146ad16f7e8649e94fb4fc21fe77e8310c060f61caaff8a
            """
        #expect(request == expectedRequest)
    }

    var awsSampleDate: Date! {
        let dateFormatter = DateFormatter()
        dateFormatter.locale = Locale(identifier: "en_US_POSIX")
        dateFormatter.dateFormat = "yyyyMMdd'T'HHmmss'Z'"
        dateFormatter.timeZone = TimeZone(secondsFromGMT: 0)
        return dateFormatter.date(from: "20130524T000000Z")
    }

    // MARK: - AWS Signer samples

    // Can be found here https://docs.aws.amazon.com/AmazonS3/latest/API/sig-v4-header-based-auth.html

    @Test func testAwsSampleGet() {
        let signer = AWSSigner(credentials: awsSampleCredentials, name: "s3", region: "us-east-1")
        var request = HTTPRequest(
            method: .get,
            url: URL(string: "https://examplebucket.s3.amazonaws.com/test.txt")!,
            headerFields: [.range: "bytes=0-9"]
        )
        signer.signHeaders(
            request: &request,
            date: self.awsSampleDate
        )
        #expect(
            request.headerFields[.authorization]
                == "AWS4-HMAC-SHA256 Credential=AKIAIOSFODNN7EXAMPLE/20130524/us-east-1/s3/aws4_request, SignedHeaders=host;range;x-amz-content-sha256;x-amz-date, Signature=f0e8bdb87c964420e857bd35b5d6ed310bd44f0170aba48dd91039c6036bdb41"
        )
    }

    @Test func testAwsSamplePut() {
        let signer = AWSSigner(credentials: awsSampleCredentials, name: "s3", region: "us-east-1")
        var request = HTTPRequest(
            method: .put,
            url: URL(string: "https://examplebucket.s3.amazonaws.com/test$file.text")!,
            headerFields: [.date: "Fri, 24 May 2013 00:00:00 GMT", .init("x-amz-storage-class")!: "REDUCED_REDUNDANCY"]
        )
        let body = Data("Welcome to Amazon S3.".utf8)
        signer.signHeaders(
            request: &request,
            body: body.bytes,
            date: self.awsSampleDate
        )
        #expect(
            request.headerFields[.authorization]
                == "AWS4-HMAC-SHA256 Credential=AKIAIOSFODNN7EXAMPLE/20130524/us-east-1/s3/aws4_request, SignedHeaders=date;host;x-amz-content-sha256;x-amz-date;x-amz-storage-class, Signature=98ad721746da40c64f1a55b78f14c238d841ea1380cd77a1b5971af0ece108bd"
        )
    }

    @Test func testAwsSampleGetBucketLifecycle() {
        let signer = AWSSigner(credentials: awsSampleCredentials, name: "s3", region: "us-east-1")
        var request = HTTPRequest(method: .get, url: URL(string: "https://examplebucket.s3.amazonaws.com/?lifecycle=")!)
        signer.signHeaders(
            request: &request,
            date: self.awsSampleDate
        )
        #expect(
            request.headerFields[.authorization]
                == "AWS4-HMAC-SHA256 Credential=AKIAIOSFODNN7EXAMPLE/20130524/us-east-1/s3/aws4_request, SignedHeaders=host;x-amz-content-sha256;x-amz-date, Signature=fea454ca298b7da1c68078a5d1bdbfbbe0d65c699e0f91ac7a200a0136783543"
        )
    }

    @Test func testAwsSampleListObjects() {
        let signer = AWSSigner(credentials: awsSampleCredentials, name: "s3", region: "us-east-1")
        var request = HTTPRequest(method: .get, url: URL(string: "https://examplebucket.s3.amazonaws.com/?max-keys=2&prefix=J")!)
        signer.signHeaders(
            request: &request,
            date: self.awsSampleDate
        )
        #expect(
            request.headerFields[.authorization]
                == "AWS4-HMAC-SHA256 Credential=AKIAIOSFODNN7EXAMPLE/20130524/us-east-1/s3/aws4_request, SignedHeaders=host;x-amz-content-sha256;x-amz-date, Signature=34b48302e7b5fa45bde8084f4b7868a86f0a534bc59db6670ed5711ef69dc6f7"
        )
    }
}
