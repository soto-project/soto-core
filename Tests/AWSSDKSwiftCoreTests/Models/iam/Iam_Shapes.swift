// THIS FILE IS COPIED FROM THE OUTPUT of https://github.com/noppoMan/aws-sdk-swift/blob/master/Sources/CodeGenerator/main.swift

import Foundation
import AWSSDKSwiftCore

struct Iam {

    public struct ServerCertificateMetadata: AWSShape {
        public static var _members: [AWSShapeMember] = [
            AWSShapeMember(label: "ServerCertificateName", required: true, type: .string),
            AWSShapeMember(label: "ServerCertificateId", required: true, type: .string),
            AWSShapeMember(label: "Arn", required: true, type: .string),
            AWSShapeMember(label: "Expiration", required: false, type: .timestamp),
            AWSShapeMember(label: "UploadDate", required: false, type: .timestamp),
            AWSShapeMember(label: "Path", required: true, type: .string)
        ]
        /// The name that identifies the server certificate.
        public let serverCertificateName: String
        ///  The stable and unique string identifying the server certificate. For more information about IDs, see IAM Identifiers in the Using IAM guide.
        public let serverCertificateId: String
        ///  The Amazon Resource Name (ARN) specifying the server certificate. For more information about ARNs and how to use them in policies, see IAM Identifiers in the Using IAM guide.
        public let arn: String
        /// The date on which the certificate is set to expire.
        public let expiration: TimeStamp?
        /// The date when the server certificate was uploaded.
        public let uploadDate: TimeStamp?
        ///  The path to the server certificate. For more information about paths, see IAM Identifiers in the Using IAM guide.
        public let path: String

        public init(serverCertificateName: String, serverCertificateId: String, arn: String, expiration: TimeStamp? = nil, uploadDate: TimeStamp? = nil, path: String) {
            self.serverCertificateName = serverCertificateName
            self.serverCertificateId = serverCertificateId
            self.arn = arn
            self.expiration = expiration
            self.uploadDate = uploadDate
            self.path = path
        }

        private enum CodingKeys: String, CodingKey {
            case serverCertificateName = "ServerCertificateName"
            case serverCertificateId = "ServerCertificateId"
            case arn = "Arn"
            case expiration = "Expiration"
            case uploadDate = "UploadDate"
            case path = "Path"
        }
    }

    public struct ListServerCertificatesResponse: AWSShape {
        public static var _members: [AWSShapeMember] = [
            AWSShapeMember(label: "Marker", required: false, type: .string),
            AWSShapeMember(label: "IsTruncated", required: false, type: .boolean),
            AWSShapeMember(label: "ServerCertificateMetadataList", required: true, type: .list)
        ]
        /// When IsTruncated is true, this element is present and contains the value to use for the Marker parameter in a subsequent pagination request.
        public let marker: String?
        /// A flag that indicates whether there are more items to return. If your results were truncated, you can make a subsequent pagination request using the Marker request parameter to retrieve more items. Note that IAM might return fewer than the MaxItems number of results even when there are more results available. We recommend that you check IsTruncated after every call to ensure that you receive all of your results.
        public let isTruncated: Bool?
        /// A list of server certificates.
        public let serverCertificateMetadataList: [ServerCertificateMetadata]

        public init(marker: String? = nil, isTruncated: Bool? = nil, serverCertificateMetadataList: [ServerCertificateMetadata]) {
            self.marker = marker
            self.isTruncated = isTruncated
            self.serverCertificateMetadataList = serverCertificateMetadataList
        }

        private enum CodingKeys: String, CodingKey {
            case marker = "Marker"
            case isTruncated = "IsTruncated"
            case serverCertificateMetadataList = "ServerCertificateMetadataList"
        }
    }
}
