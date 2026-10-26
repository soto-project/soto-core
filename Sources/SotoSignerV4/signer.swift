//===----------------------------------------------------------------------===//
//
// This source file is part of the Soto for AWS open source project
//
// Copyright (c) 2017-2026 the Soto project authors
// Licensed under Apache License v2.0
//
// See LICENSE.txt for license information
// See CONTRIBUTORS.txt for the list of Soto project authors
//
// SPDX-License-Identifier: Apache-2.0
//
//===----------------------------------------------------------------------===//

import Crypto
public import HTTPTypes

#if canImport(FoundationEssentials)
public import FoundationEssentials
#else
public import Foundation
#endif

/// Amazon Web Services V4 Signer
public struct AWSSigner: Sendable {

    /// The algorithm used to create the hash of the canonical request
    @nonexhaustive
    public enum Algorithm: String, Sendable {
        case sigV4 = "AWS4-HMAC-SHA256"
        case sigV4a = "AWS4-ECDSA-P256-SHA256"

        var name: String { self.rawValue }
    }

    @nonexhaustive
    public enum Payload: Sendable {
        /// No payload
        case empty
        /// Don't use body when signing request
        case unsignedPayload

        var hashedPayload: String {
            switch self {
            case .empty:
                Self.hashedEmptyBody
            case .unsignedPayload:
                "UNSIGNED-PAYLOAD"
            }
        }

        static let hashedEmptyBody = SHA256.hash(data: [UInt8]()).hexDigest()
    }

    /// Security credentials for accessing AWS services
    public let credentials: Credential
    /// Service signing name. In general this is the same as the service name
    public let name: String
    /// AWS region you are working in
    public let region: String
    /// Signing algorithm
    public let algorithm: Algorithm

    /// Initialise the Signer class with AWS credentials
    public init(credentials: Credential, name: String, region: String) {
        self.credentials = credentials
        self.name = name
        self.region = region
        self.algorithm = .sigV4
    }

    /// Initialise the Signer class with AWS credentials
    public init(credentials: Credential, name: String, region: String, algorithm: Algorithm) {
        self.credentials = credentials
        self.name = name
        self.region = region
        self.algorithm = algorithm
    }

    /// Process URL before signing headers
    ///
    /// `signHeaders` makes assumptions about the URLs they are provided, this function cleans up a URL so it is ready
    /// to be signed by either of these functions. It sorts the query params and ensures they are properly percent encoded
    public func processURL(url: URL) -> URL? {
        guard var urlComponents = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return nil }
        let query = urlComponents.percentEncodedQueryItems?
            .sorted {
                if $0.name < $1.name { return true }
                if $0.name > $1.name { return false }
                guard let value1 = $0.value, let value2 = $1.value else { return false }
                return value1 < value2
            }
            .map { item in
                item.value.map { "\(item.name)=\($0.addingAWSPercentEncoding(forURLComponent: [.uriEncode, .percent]))" } ?? "\(item.name)="
            }
            .joined(separator: "&")
        urlComponents.percentEncodedQuery = query
        // S3 requires "+" encoded in the URL
        if self.name == "s3" {
            urlComponents.percentEncodedPath = urlComponents.percentEncodedPath.addingAWSPercentEncoding(forURLComponent: [.s3Path, .percent])
        }
        return urlComponents.url
    }

    /// Generate signed headers, for an HTTP request using the AWS sigV4 algorithm.
    ///
    /// The supplied HTTP request is updated with the additional headers.
    ///
    /// - Parameters:
    ///   - request: HTTP request
    ///   - body: Request body bytes
    ///   - omitSecurityToken: Should we include security token in the query parameters
    ///   - date: Date that URL is valid from, defaults to now
    public func signHeaders(
        request: inout HTTPRequest,
        body: RawSpan,
        omitSecurityToken: Bool = false,
        date: Date = Date()
    ) {
        let hashedPayload = SHA256.hash(bytes: body).hexDigest()
        return signHeaders(request: &request, hashedPayload: hashedPayload, omitSecurityToken: omitSecurityToken, date: date)
    }

    /// Generate signed headers, for an HTTP request using the AWS sigV4 algorithm.
    ///
    /// The supplied HTTP request is updated with the additional headers.
    ///
    /// - Parameters:
    ///   - request: HTTP request
    ///   - payload: Empty payload or unsigned payload
    ///   - omitSecurityToken: Should we include security token in the query parameters
    ///   - date: Date that URL is valid from, defaults to now
    public func signHeaders(
        request: inout HTTPRequest,
        payload: Payload = .empty,
        omitSecurityToken: Bool = false,
        date: Date = Date()
    ) {
        signHeaders(request: &request, hashedPayload: payload.hashedPayload, omitSecurityToken: omitSecurityToken, date: date)
    }

    /// Generate signed headers, for an HTTP request using the AWS sigV4 algorithm.
    ///
    /// The supplied HTTP request is updated with the additional headers.
    ///
    /// - Parameters:
    ///   - request: HTTP request
    ///   - body: Request body
    ///   - omitSecurityToken: Should we include security token in the query parameters
    ///   - date: Date that URL is valid from, defaults to now
    func signHeaders(
        request: inout HTTPRequest,
        hashedPayload: String,
        omitSecurityToken: Bool = false,
        date: Date = Date()
    ) {
        guard let url = request.url else { return }

        request.authority = Self.hostname(from: url)

        let dateString = Self.timestamp(date)
        // add date, host, sha256 and if available security token headers
        request.headerFields[.xAmzDate] = dateString
        request.headerFields[.xAmzContentSha256] = hashedPayload
        if algorithm == .sigV4a {
            request.headerFields[.xAmzRegionSet] = self.region
        }
        if !omitSecurityToken, let sessionToken = credentials.sessionToken {
            request.headerFields[.xAmzSecurityToken] = sessionToken
        }
        // construct signing data. Do this after adding the headers as it uses data from the headers
        let signingData = AWSSigner.SigningData(
            url: url,
            request: request,
            hashedPayload: hashedPayload,
            date: dateString,
            signer: self
        )

        let credential =
            switch algorithm {
            case .sigV4:
                "\(self.credentials.accessKeyId)/\(signingData.date)/\(self.region)/\(self.name)/aws4_request"
            case .sigV4a:
                "\(self.credentials.accessKeyId)/\(signingData.date)/\(self.name)/aws4_request"
            }

        // construct authorization string
        let authorization =
            """
            \(algorithm.name) \
            Credential=\(credential), \
            SignedHeaders=\(signingData.signedHeaders), \
            Signature=\(self.signature(signingData: signingData, algorithm: algorithm))
            """

        // add Authorization header
        request.headerFields[.authorization] = authorization
        // now we have signed the request we can add the security token if required
        if omitSecurityToken, let sessionToken = credentials.sessionToken {
            request.headerFields[.xAmzSecurityToken] = sessionToken
        }
    }

    /// Generate a signed URL, for a HTTP request
    ///
    /// If you are signing a URL using sigV4a then you should supply a `X-Amz-Region-Set` header
    /// including the regions you want to use.
    ///
    /// - Parameters:
    ///   - request: HTTP request
    ///   - expires: How long before the signed URL expires
    ///   - omitSecurityToken: Should we include security token in the query parameters
    ///   - date: Date that URL is valid from, defaults to now
    /// - Returns: Signed URL
    public func signURL(
        request: HTTPRequest,
        expires: Duration,
        omitSecurityToken: Bool = false,
        date: Date = Date()
    ) -> URL? {
        let hashedPayload = Payload.unsignedPayload.hashedPayload
        return signURL(request: request, hashedPayload: hashedPayload, expires: expires, omitSecurityToken: omitSecurityToken, date: date)
    }

    /// Generate a signed URL, for a HTTP request
    ///
    /// If you are signing a URL using sigV4a then you should supply a `X-Amz-Region-Set` header
    /// including the regions you want to use.
    ///
    /// - Parameters:
    ///   - request: HTTP request
    ///   - body: Request body
    ///   - expires: How long before the signed URL expires
    ///   - omitSecurityToken: Should we include security token in the query parameters
    ///   - date: Date that URL is valid from, defaults to now
    /// - Returns: Signed URL
    func signURL(
        request: HTTPRequest,
        hashedPayload: String,
        expires: Duration,
        omitSecurityToken: Bool = false,
        date: Date = Date()
    ) -> URL? {
        guard let scheme = request.scheme, let authority = request.authority, let path = request.path else { return nil }
        guard var urlComponents = URLComponents(string: "\(scheme)://\(authority)\(path)") else { return nil }
        // Percent encode path
        if self.name == "s3" {
            urlComponents.percentEncodedPath = urlComponents.percentEncodedPath.addingAWSPercentEncoding(forURLComponent: [.s3Path, .percent])
        }
        let url = urlComponents.url!
        // Create signing data
        var signingData = AWSSigner.SigningData(url: url, request: request, hashedPayload: hashedPayload, date: Self.timestamp(date), signer: self)
        // Construct query string. Start with original query strings and append all the signing info.
        var query = urlComponents.query ?? ""
        if query.count > 0 {
            query += "&"
        }
        query += "X-Amz-Algorithm=\(algorithm.name)"
        switch algorithm {
        case .sigV4:
            query += "&X-Amz-Credential=\(self.credentials.accessKeyId)%2F\(signingData.date)%2F\(self.region)%2F\(self.name)%2Faws4_request"
        case .sigV4a:
            query += "&X-Amz-Credential=\(self.credentials.accessKeyId)%2F\(signingData.date)%2F\(self.name)%2Faws4_request"
            query += "&X-Amz-Region-Set=\(self.region)"
        }

        query += "&X-Amz-Date=\(signingData.datetime)"
        query += "&X-Amz-Expires=\(expires.components.seconds)"
        query += "&X-Amz-SignedHeaders=\(signingData.signedHeaders.uriEncode())"
        if !omitSecurityToken, let sessionToken = credentials.sessionToken {
            query += "&X-Amz-Security-Token=\(sessionToken.uriEncode())"
        }
        // Split the string and sort to ensure the order of query strings is the same as AWS
        query = query.split(separator: "&")
            .sorted()
            .joined(separator: "&")
            .addingAWSPercentEncoding(forURLComponent: [.query, .percent])
        urlComponents.percentEncodedQuery = query
        // update unsignedURL in the signingData so when the canonical request is constructed it includes all the signing query items
        signingData.unsignedURL = urlComponents.url!  // NEED TO DEAL WITH SITUATION WHERE THIS FAILS
        query += "&X-Amz-Signature=\(self.signature(signingData: signingData, algorithm: algorithm))"
        if omitSecurityToken, let sessionToken = credentials.sessionToken {
            query += "&X-Amz-Security-Token=\(sessionToken.uriEncode())"
        }
        urlComponents.percentEncodedQuery = query

        return urlComponents.url!
    }

    /// Temporary structure passed from calls to `startSigningChunks` and
    /// subsequent calls to `signChunk`
    public struct ChunkedSigningData {
        /// signature for streamed data
        public let signature: String
        let datetime: String
        let signingKey: SymmetricKey
    }

    /// Start the process of signing a s3 chunked upload.
    ///
    /// Update headers and generate first signature. See https://docs.aws.amazon.com/AmazonS3/latest/API/sigv4-streaming.html
    /// for more details
    /// - Parameters:
    ///   - url: url
    ///   - method: http method
    ///   - headers: original headers
    ///   - date: date to use for signing
    /// - Returns: Tuple of updated headers and signing data to use in first call to `signChunk`
    public func startSigningChunks(
        request: inout HTTPRequest,
        date: Date = Date()
    ) -> ChunkedSigningData? {
        self.startSigningChunks(request: &request, date: date, algorithm: .sigV4)
    }

    /// Start the process of signing a s3 chunked upload.
    ///
    /// Update headers and generate first signature. See https://docs.aws.amazon.com/AmazonS3/latest/API/sigv4-streaming.html
    /// for more details
    /// - Parameters:
    ///   - url: url
    ///   - method: http method
    ///   - headers: original headers
    ///   - date: date to use for signing
    ///   - algorithm: Signing algorithm (sigV4 or sigV4a)
    /// - Returns: Tuple of updated headers and signing data to use in first call to `signChunk`
    public func startSigningChunks(
        request: inout HTTPRequest,
        date: Date = Date(),
        algorithm: Algorithm
    ) -> ChunkedSigningData? {
        guard let url = request.url else { return nil }

        request.authority = Self.hostname(from: url)
        let bodyHash = "STREAMING-AWS4-HMAC-SHA256-PAYLOAD"
        let dateString = AWSSigner.timestamp(date)
        // add date, host, sha256 and if available security token headers
        request.headerFields[.xAmzDate] = dateString
        request.headerFields[.xAmzContentSha256] = bodyHash
        if let sessionToken = credentials.sessionToken {
            request.headerFields[.xAmzSecurityToken] = sessionToken
        }
        // remove content-length header
        request.headerFields[.contentLength] = nil

        // construct signing data. Do this after adding the headers as it uses data from the headers
        let signingData = AWSSigner.SigningData(url: url, request: request, hashedPayload: bodyHash, date: dateString, signer: self)
        let signingKey = self.signingKey(date: signingData.date)
        let signature = self.signature(signingData: signingData, algorithm: algorithm)
        let chunkedSigningData = ChunkedSigningData(signature: signature, datetime: signingData.datetime, signingKey: signingKey)

        // construct authorization string
        let authorization =
            "\(algorithm.name) " + "Credential=\(credentials.accessKeyId)/\(signingData.date)/\(self.region)/\(self.name)/aws4_request, "
            + "SignedHeaders=\(signingData.signedHeaders), " + "Signature=\(signature)"

        // add Authorization header
        request.headerFields[.authorization] = authorization

        return chunkedSigningData
    }

    /// Generate the signature for a chunk in a s3 chunked upload
    /// - Parameters:
    ///   - body: Body of chunk
    ///   - signingData: Signing data returned from previous `signChunk` or `startSigningChunk` if this is the first call
    /// - Returns: signing data that includes the signature and other data that is required for signing the next chunk
    public func signChunk(body: RawSpan, signingData: ChunkedSigningData) -> ChunkedSigningData {
        let stringToSign = self.chunkStringToSign(
            hashedPayload: SHA256.hash(bytes: body).hexDigest(),
            previousSignature: signingData.signature,
            datetime: signingData.datetime
        )
        let signature = HMAC<SHA256>.authenticationCode(for: [UInt8](stringToSign.utf8), using: signingData.signingKey).hexDigest()
        return ChunkedSigningData(signature: signature, datetime: signingData.datetime, signingKey: signingData.signingKey)
    }

    /// Generate the signature for a chunk in a s3 chunked upload
    /// - Parameters:
    ///   - body: Body of chunk
    ///   - signingData: Signing data returned from previous `signChunk` or `startSigningChunk` if this is the first call
    /// - Returns: signing data that includes the signature and other data that is required for signing the next chunk
    public func signLastChunk(signingData: ChunkedSigningData) -> ChunkedSigningData {
        let stringToSign = self.chunkStringToSign(
            hashedPayload: Payload.hashedEmptyBody,
            previousSignature: signingData.signature,
            datetime: signingData.datetime
        )
        let signature = HMAC<SHA256>.authenticationCode(for: [UInt8](stringToSign.utf8), using: signingData.signingKey).hexDigest()
        return ChunkedSigningData(signature: signature, datetime: signingData.datetime, signingKey: signingData.signingKey)
    }

    /// structure used to store data used throughout the signing process
    struct SigningData {
        let url: URL
        let method: HTTPRequest.Method
        let authority: String?
        let hashedPayload: String
        let datetime: String
        let headersToSign: HTTPFields
        let signedHeaders: String
        var unsignedURL: URL

        var date: String { String(self.datetime.prefix(8)) }

        init(
            url: URL,
            request: HTTPRequest,
            hashedPayload: String,
            date: String,
            signer: AWSSigner
        ) {
            self.url = url
            self.method = request.method
            self.datetime = date
            self.unsignedURL = self.url
            self.authority = request.authority
            self.hashedPayload = hashedPayload

            // from S3 V4 signed documentation
            // The CanonicalHeaders list must include the following:
            // - HTTP host header.
            // If the Content-Type header is present in the request, you must add it to the CanonicalHeaders list.
            // Any x-amz-* headers that you plan to include in your request must also be added. For example, if
            // you are using temporary security credentials, you need to include x-amz-security-token in your request.
            // You must add this header in the list of CanonicalHeaders.
            let headersNotToSign: Set<HTTPField.Name> = [
                .authorization,
                .contentLength,
                .expect,
                .userAgent,
            ]
            var headersToSign = request.headerFields.filter({ !headersNotToSign.contains($0.name) })
            headersToSign[._host] = request.authority
            self.headersToSign = headersToSign
            self.signedHeaders = self.headersToSign.lazy.map { $0.name.canonicalName }.sorted().joined(separator: ";")
        }
    }

    // Stage 3 Calculating signature as in https://docs.aws.amazon.com/general/latest/gr/sigv4-calculate-signature.html
    func signature(signingData: SigningData, algorithm: Algorithm) -> String {
        switch algorithm {
        case .sigV4:
            return self.signV4(signingData)
        case .sigV4a:
            return self.signV4a(signingData)
        }
    }

    // Stage 3a Calculating signature as in https://docs.aws.amazon.com/general/latest/gr/sigv4-calculate-signature.html
    func signV4(_ signingData: SigningData) -> String {
        let signingKey = self.signingKey(date: signingData.date)
        let kSignature = HMAC<SHA256>.authenticationCode(
            for: [UInt8](self.stringToSign(signingData: signingData, algorithm: .sigV4).utf8),
            using: signingKey
        )
        return kSignature.hexDigest()
    }

    func signV4a(_ signingData: SigningData) -> String {
        let signingKey = SigV4aKeyPair(credential: self.credentials)
        let stringToSign = self.stringToSign(signingData: signingData, algorithm: .sigV4a)
        let signature = try! signingKey.sign(stringToSign)
        return signature
    }

    /// Stage 2 Create the string to sign as in https://docs.aws.amazon.com/general/latest/gr/sigv4-create-string-to-sign.html
    func stringToSign(signingData: SigningData, algorithm: Algorithm) -> String {
        switch algorithm {
        case .sigV4:
            """
            \(algorithm.name)\n\
            \(signingData.datetime)\n\
            \(signingData.date)/\(self.region)/\(self.name)/aws4_request\n\
            \(SHA256.hash(data: [UInt8](self.canonicalRequest(signingData: signingData).utf8)).hexDigest())
            """
        case .sigV4a:
            """
            \(algorithm.name)\n\
            \(signingData.datetime)\n\
            \(signingData.date)/\(self.name)/aws4_request\n\
            \(SHA256.hash(data: [UInt8](self.canonicalRequest(signingData: signingData).utf8)).hexDigest())
            """
        }

    }

    /// Stage 1 Create the canonical request as in https://docs.aws.amazon.com/general/latest/gr/sigv4-create-canonical-request.html
    func canonicalRequest(signingData: SigningData) -> String {
        let canonicalHeaders = signingData.headersToSign
            .lazy
            .map { (key: $0.name.canonicalName, value: $0.value) }
            .sorted { $0.key < $1.key }
            .map { "\($0.key):\($0.value._trimming(while: \.isWhitespace).removeSequentialWhitespace())" }
            .joined(separator: "\n")
        let canonicalPath: String
        let urlComps = URLComponents(url: signingData.unsignedURL, resolvingAgainstBaseURL: false)!
        if self.name == "s3" {
            canonicalPath = urlComps.path.uriPathEncode()
        } else {
            // non S3 paths need to be encoded twice
            canonicalPath = urlComps.percentEncodedPath.uriPathEncode()
        }
        let canonicalRequest =
            "\(signingData.method.rawValue)\n" + "\(canonicalPath)\n" + "\(signingData.unsignedURL.query ?? "")\n"  // assuming query parameters have are already percent encoded correctly
            + "\(canonicalHeaders)\n\n" + "\(signingData.signedHeaders)\n" + signingData.hashedPayload
        return canonicalRequest
    }

    /// get signing key
    func signingKey(date: String) -> SymmetricKey {
        let kDate = HMAC<SHA256>.authenticationCode(
            for: [UInt8](date.utf8),
            using: SymmetricKey(data: Array("AWS4\(self.credentials.secretAccessKey)".utf8))
        )
        let kRegion = HMAC<SHA256>.authenticationCode(for: [UInt8](self.region.utf8), using: SymmetricKey(data: kDate))
        let kService = HMAC<SHA256>.authenticationCode(for: [UInt8](self.name.utf8), using: SymmetricKey(data: kRegion))
        let kSigning = HMAC<SHA256>.authenticationCode(for: [UInt8]("aws4_request".utf8), using: SymmetricKey(data: kService))
        return SymmetricKey(data: kSigning)
    }

    /// chunked upload string to sign
    func chunkStringToSign(hashedPayload: String, previousSignature: String, datetime: String) -> String {
        let date = String(datetime.prefix(8))
        let stringToSign =
            "AWS4-HMAC-SHA256-PAYLOAD\n" + "\(datetime)\n" + "\(date)/\(region)/\(name)/aws4_request\n" + "\(previousSignature)\n"
            + "\(Payload.hashedEmptyBody)\n" + hashedPayload
        return stringToSign
    }

    /// Create a SHA256 hash of the Requests body
    /*static func hashedPayload(_ payload: BodyData?) -> String {
        guard let payload else { return self.hashedEmptyBody }
        let hash: String?
        switch payload {
        case .string(let string):
            hash = SHA256.hash(data: [UInt8](string.utf8)).hexDigest()
        case .data(let data):
            hash = SHA256.hash(data: data).hexDigest()
        case .byteBuffer(let byteBuffer):
            let byteBufferView = byteBuffer.readableBytesView
            hash = byteBufferView.withContiguousStorageIfAvailable { bytes in
                SHA256.hash(data: bytes).hexDigest()
            }
        case .unsignedPayload:
            return "UNSIGNED-PAYLOAD"
        case .s3chunked:
            return "STREAMING-AWS4-HMAC-SHA256-PAYLOAD"
        }
        if let hash {
            return hash
        } else {
            return self.hashedEmptyBody
        }
    }*/

    #if os(macOS) || os(iOS) || os(tvOS) || os(watchOS) || os(visionOS)
    private static let timeStampDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd'T'HHmmss'Z'"
        formatter.timeZone = TimeZone(abbreviation: "UTC")
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter
    }()
    #endif

    /// return a timestamp formatted for signing requests
    static func timestamp(_ date: Date) -> String {
        #if os(macOS) || os(iOS) || os(tvOS) || os(watchOS) || os(visionOS)
        if #available(macOS 12, iOS 15, tvOS 15, watchOS 8, *) {
            Date.ISO8601FormatStyle().dateSeparator(.omitted).timeSeparator(.omitted).format(date)
        } else {
            self.timeStampDateFormatter.string(from: date)
        }
        #else
        Date.ISO8601FormatStyle().dateSeparator(.omitted).timeSeparator(.omitted).format(date)
        #endif
    }

    /// returns port from URL. If port is set to 80 on an http url or 443 on an https url nil is returned
    private static func port(from url: URL) -> Int? {
        guard let port = url.port else { return nil }
        guard url.scheme != "http" || port != 80 else { return nil }
        guard url.scheme != "https" || port != 443 else { return nil }
        return port
    }

    private static func hostname(from url: URL) -> String {
        "\(url.host ?? "")\(self.port(from: url).map { ":\($0)" } ?? "")"
    }
}

extension StringProtocol {
    func s3PathEncode() -> String {
        self.addingAWSPercentEncoding(forURLComponent: .s3Path)
    }

    func uriEncode() -> String {
        self.addingAWSPercentEncoding(forURLComponent: .uriEncode)
    }

    func uriPathEncode() -> String {
        self.addingAWSPercentEncoding(forURLComponent: .uriEncodePath)
    }
}

extension URL {
    /// return URL path, but do not remove the slash at the end if it exists.
    ///
    /// There doesn't seem to be anyway to do this without parsing the path myself
    /// If I could guarantee macOS 10.11 then I could use `hasDirectoryPath`.
    package var pathWithSlash: String {
        let relativeString = self.relativeString
        let doesPathEndInSlash: Bool
        // does path end in "/"
        if let questionMark = relativeString.firstIndex(of: "?") {
            let prevCharacter = relativeString.index(before: questionMark)
            doesPathEndInSlash = (relativeString[prevCharacter] == "/")
        } else if let hashCharacter = relativeString.firstIndex(of: "#") {
            let prevCharacter = relativeString.index(before: hashCharacter)
            doesPathEndInSlash = (relativeString[prevCharacter] == "/")
        } else {
            let prevCharacter = relativeString.index(before: relativeString.endIndex)
            doesPathEndInSlash = (relativeString[prevCharacter] == "/")
        }
        var path = self.path
        if doesPathEndInSlash, path != "/" {
            path += "/"
        }
        return path
    }
}

extension StringProtocol {
    /// Remove whitespace that follows whitespace
    fileprivate func removeSequentialWhitespace() -> String {
        reduce(into: "") { result, character in
            if result.last?.isWhitespace != true || character.isWhitespace == false {
                result.append(character)
            }
        }
    }

    /// Version of String.trimmingCharacters which returns a SubSequence
    fileprivate func _trimming(while predicate: (Element) throws -> Bool) rethrows -> SubSequence {
        guard let startIndex = try self.firstIndex(where: { try !predicate($0) }) else { return self[self.startIndex..<self.startIndex] }
        guard try self.last.map(predicate) == true else { return self[startIndex...] }
        guard let endIndex = try self.lastIndex(where: predicate) else { return self[self.startIndex..<self.startIndex] }
        return self[startIndex..<endIndex]
    }
}

extension HTTPField.Name {
    /// HTTPFields shouldn't really include a host field as that is
    /// stored in the HTTPRequest authority
    @inlinable
    static var _host: Self {
        .init("Host")!
    }

    @inlinable
    static var xAmzDate: Self {
        .init("X-Amz-Date")!
    }

    @inlinable
    static var xAmzContentSha256: Self {
        .init("X-Amz-Content-Sha256")!
    }

    @inlinable
    static var xAmzRegionSet: Self {
        .init("X-Amz-Region-Set")!
    }

    @inlinable
    static var xAmzSecurityToken: Self {
        .init("X-Amz-Security-Token")!
    }
}
