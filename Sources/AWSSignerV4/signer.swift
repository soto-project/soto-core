//
//  signer.swift
//  AWSSigner
//
//  Created by Adam Fowler on 2019/08/29.
//  Amazon Web Services V4 Signer
//  AWS documentation about signing requests is here https://docs.aws.amazon.com/general/latest/gr/signing_aws_api_requests.html
//

import struct Foundation.CharacterSet
import struct Foundation.Data
import struct Foundation.Date
import class Foundation.DateFormatter
import struct Foundation.Locale
import struct Foundation.TimeZone
import struct Foundation.URL
import NIO
import NIOHTTP1

/// Amazon Web Services V4 Signer
public struct AWSSigner {
    /// security credentials for accessing AWS services
    public let credentials: Credential
    /// service signing name. In general this is the same as the service name
    public let name: String
    /// AWS region you are working in
    public let region: String
    
    static let hashedEmptyBody = sha256([UInt8]()).hexEncoded()
    
    static private let timeStampDateFormatter: DateFormatter = createTimeStampDateFormatter()
    
    /// Initialise the Signer class with AWS credentials
    public init(credentials: Credential, name: String, region: String) {
        self.credentials = credentials
        self.name = name
        self.region = region
    }
    
    /// Enum for holding your body data
    public enum BodyData {
        case string(String)
        case data(Data)
        case byteBuffer(ByteBuffer)
    }
    
    public func signHeaders<Buffer: Collection>(
        url: URL,
        method: HTTPMethod = .GET,
        headers: HTTPHeaders = HTTPHeaders(),
        body: Buffer,
        date: Date = Date()
    ) -> HTTPHeaders where Buffer.Element == UInt8 {
        let payloadHash = AWSSigner.hashedPayload(body)
        return signHeaders(url: url, method: method, headers: headers, payloadHash: payloadHash, date: date)
    }
    
    public func signHeaders(url: URL, method: HTTPMethod = .GET, headers: HTTPHeaders = HTTPHeaders(), date: Date = Date()) -> HTTPHeaders {
        return signHeaders(url: url, method: method, headers: headers, payloadHash: AWSSigner.hashedEmptyBody, date: date)
    }
    
    /// Generate signed headers, for a HTTP request
    private func signHeaders(url: URL, method: HTTPMethod, headers: HTTPHeaders, payloadHash: String, date: Date) -> HTTPHeaders {
        let dateString = AWSSigner.timestamp(date)
        var headers = headers
        // add date, host, sha256 and if available security token headers
        headers.add(name: "X-Amz-Date", value: dateString)
        headers.add(name: "host", value: url.host ?? "")
        headers.add(name: "x-amz-content-sha256", value: payloadHash)
        if let sessionToken = credentials.sessionToken {
            headers.add(name: "x-amz-security-token", value: sessionToken)
        }
        
        // construct signing data. Do this after adding the headers as it uses data from the headers
        let signingData = AWSSigner.SigningData(url: url, method: method, headers: headers, payloadHash: payloadHash, date: dateString, signer: self)
        
        // construct authorization string
        let authorization = "AWS4-HMAC-SHA256 " +
            "Credential=\(credentials.accessKeyId)/\(signingData.date)/\(region)/\(name)/aws4_request, " +
            "SignedHeaders=\(signingData.signedHeaders), " +
        "Signature=\(signature(signingData: signingData))"
        
        // add Authorization header
        headers.add(name: "Authorization", value: authorization)
        
        return headers
    }
    
    public func signURL<Buffer: Collection>(
        url: URL,
        method: HTTPMethod = .GET,
        body: Buffer,
        date: Date = Date(),
        expires: Int = 86400
    ) -> URL where Buffer.Element == UInt8 {
        let payloadHash: String
        if name == "s3" {
            payloadHash = "UNSIGNED-PAYLOAD"
        } else {
            payloadHash = AWSSigner.hashedPayload(body)
        }
        return signURL(url: url, method: method, payloadHash: payloadHash, date: date, expires: expires)
    }
    
    public func signURL(url: URL, method: HTTPMethod = .GET, headers: HTTPHeaders = HTTPHeaders(), date: Date = Date(), expires: Int = 86400) -> URL {
        return signURL(url: url, method: method, payloadHash: AWSSigner.hashedEmptyBody, date: date, expires: expires)
    }
    
    /// Generate a signed URL, for a HTTP request
    public func signURL(url: URL, method: HTTPMethod, payloadHash: String, date: Date, expires: Int) -> URL {
        let headers = HTTPHeaders([("host", url.host ?? "")])
        // Create signing data
        let signingData = AWSSigner.SigningData(url: url, method: method, headers: headers, payloadHash: payloadHash, date: AWSSigner.timestamp(date), signer: self)
        
        // Construct query string. Start with original query strings and append all the signing info.
        var query = url.query ?? ""
        if query.count > 0 {
            query += "&"
        }
        query += "X-Amz-Algorithm=AWS4-HMAC-SHA256"
        query += "&X-Amz-Credential=\(credentials.accessKeyId)/\(signingData.date)/\(region)/\(name)/aws4_request"
        query += "&X-Amz-Date=\(signingData.datetime)"
        query += "&X-Amz-Expires=\(expires)"
        query += "&X-Amz-SignedHeaders=\(signingData.signedHeaders)"
        if let sessionToken = credentials.sessionToken {
            query += "&X-Amz-Security-Token=\(sessionToken.uriEncode())"
        }
        // Split the string and sort to ensure the order of query strings is the same as AWS
        query = query.split(separator: "&")
            .sorted()
            .joined(separator: "&")
            .queryEncode()
        
        // update unsignedURL in the signingData so when the canonical request is constructed it includes all the signing query items
        signingData.unsignedURL = URL(string: url.absoluteString.split(separator: "?")[0]+"?"+query)! // NEED TO DEAL WITH SITUATION WHERE THIS FAILS
        query += "&X-Amz-Signature=\(signature(signingData: signingData))"
        
        // Add signature to query items and build a new Request
        let signedURL = URL(string: url.absoluteString.split(separator: "?")[0]+"?"+query)!

        return signedURL
    }
    
    /// structure used to store data used throughout the signing process
    class SigningData {
        let url : URL
        let method : HTTPMethod
        let payloadHash : String
        let datetime : String
        let headersToSign: [String: String]
        let signedHeaders : String
        var unsignedURL : URL
        
        var date : String { return String(datetime.prefix(8))}
        
        init(url: URL, method: HTTPMethod, headers: HTTPHeaders, payloadHash: String, date: String, signer: AWSSigner) {
            self.url = url
            self.method = method
            self.datetime = date
            self.unsignedURL = self.url
            self.payloadHash = payloadHash

            let headersNotToSign: Set<String> = [
                "Authorization"
            ]
            var headersToSign: [String: String] = [:]
            var signedHeadersArray: [String] = []
            for header in headers {
                if headersNotToSign.contains(header.name) {
                    continue
                }
                headersToSign[header.name] = header.value
                signedHeadersArray.append(header.name.lowercased())
            }
            self.headersToSign = headersToSign
            self.signedHeaders = signedHeadersArray.sorted().joined(separator: ";")
        }
    }
    
    // Stage 3 Calculating signature as in https://docs.aws.amazon.com/general/latest/gr/sigv4-calculate-signature.html
    func signature(signingData: SigningData) -> String {
        let kDate = hmac(string:signingData.date, key:Array("AWS4\(credentials.secretAccessKey)".utf8))
        let kRegion = hmac(string: region, key: kDate)
        let kService = hmac(string: name, key: kRegion)
        let kSigning = hmac(string: "aws4_request", key: kService)
        let kSignature = hmac(string: stringToSign(signingData: signingData), key: kSigning)
        return kSignature.hexEncoded()
    }
    
    /// Stage 2 Create the string to sign as in https://docs.aws.amazon.com/general/latest/gr/sigv4-create-string-to-sign.html
    func stringToSign(signingData: SigningData) -> String {
        let stringToSign = "AWS4-HMAC-SHA256\n" +
            "\(signingData.datetime)\n" +
            "\(signingData.date)/\(region)/\(name)/aws4_request\n" +
            sha256(canonicalRequest(signingData: signingData)).hexEncoded()
        return stringToSign
    }
    
    /// Stage 1 Create the canonical request as in https://docs.aws.amazon.com/general/latest/gr/sigv4-create-canonical-request.html
    func canonicalRequest(signingData: SigningData) -> String {
        let canonicalHeaders = signingData.headersToSign.map { return "\($0.key.lowercased()):\($0.value.trimmingCharacters(in: CharacterSet.whitespaces))" }
            .sorted()
            .joined(separator: "\n")
        let canonicalRequest = "\(signingData.method.rawValue)\n" +
            "\(signingData.unsignedURL.path.uriEncodeWithSlash())\n" +
            "\(signingData.unsignedURL.query ?? "")\n" +        // should really uriEncode all the query string values
            "\(canonicalHeaders)\n\n" +
            "\(signingData.signedHeaders)\n" +
            signingData.payloadHash
        return canonicalRequest
    }
    
    /// Create a SHA256 hash of the Requests body
    static func hashedPayload<Buffer: Collection>(_ payload: Buffer) -> String where Buffer.Element == UInt8 {
        let hash = payload.withContiguousStorageIfAvailable { bytes in
            return sha256(bytes)
        }
        return hash?.hexEncoded() ?? AWSSigner.hashedEmptyBody
/*        guard let payload = payload else { return hashedEmptyBody }
        let hash : [UInt8]?
        switch payload {
        case .string(let string):
            hash = sha256(string)
        case .data(let data):
            hash = data.withUnsafeBytes { bytes in
                return sha256(bytes.bindMemory(to: UInt8.self))
            }
        case .byteBuffer(let byteBuffer):
            let byteBufferView = byteBuffer.readableBytesView
            hash = byteBufferView.withContiguousStorageIfAvailable { bytes in
                return sha256(bytes)
            }
        }
        if let hash = hash {
            return AWSSigner.hexEncoded(hash)
        } else {
            return hashedEmptyBody
        }*/
    }
    
    /// return a hexEncoded string buffer from an array of bytes
    /*static func hexEncoded(_ buffer: [UInt8]) -> String {
        return buffer.map{String(format: "%02x", $0)}.joined(separator: "")
    }*/
    
    /// create timestamp dateformatter
    static private func createTimeStampDateFormatter() -> DateFormatter {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd'T'HHmmss'Z'"
        formatter.timeZone = TimeZone(abbreviation: "UTC")
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter
    }
    
    /// return a timestamp formatted for signing requests
    static func timestamp(_ date: Date) -> String {
        return timeStampDateFormatter.string(from: date)
    }
}

extension String {
    func queryEncode() -> String {
        return addingPercentEncoding(withAllowedCharacters: String.queryAllowedCharacters) ?? self
    }
    
    func uriEncode() -> String {
        return addingPercentEncoding(withAllowedCharacters: String.uriAllowedCharacters) ?? self
    }
    
    func uriEncodeWithSlash() -> String {
        return addingPercentEncoding(withAllowedCharacters: String.uriAllowedWithSlashCharacters) ?? self
    }
    
    static let uriAllowedWithSlashCharacters = CharacterSet(charactersIn:"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~/")
    static let uriAllowedCharacters = CharacterSet(charactersIn:"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")
    static let queryAllowedCharacters = CharacterSet(charactersIn:"/;+").inverted
}

extension Collection where Element == UInt8 {
    func hexEncoded() -> String {
        return self.map{String(format: "%02x", $0)}.joined(separator: "")
    }
}
