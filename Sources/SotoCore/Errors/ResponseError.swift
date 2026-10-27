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

public import HTTPTypes

public struct AWSResponseError: AWSErrorType, Decodable {
    public let errorCode: String
    public let message: String?
    public let response: HTTPResponse?

    init(errorCode: String, message: String? = nil, response: HTTPResponse? = nil) {
        self.errorCode = errorCode
        self.message = message
        self.response = response
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        let responseContainer = decoder.userInfo[.awsResponse]! as! ResponseDecodingContainer
        self.errorCode = try container.decode(AWSErrorCode.self).code
        self.message = try container.decode(AWSErrorMessage.self).message
        self.response = responseContainer.response.response
    }

    /// Access has been denied.
    public static var accessDenied: AWSResponseError { .init(errorCode: "AccessDenied") }
    /// The request signature does not conform to AWS standards.
    public static var incompleteSignature: AWSResponseError { .init(errorCode: "IncompleteSignature") }
    /// The action or operation requested is not valid. Verify that the action is typed correctly.
    public static var invalidAction: AWSResponseError { .init(errorCode: "InvalidAction") }
    /// The X.509 certificate or AWS access key ID provided does not exist in our records.
    public static var invalidClientTokenId: AWSResponseError { .init(errorCode: "InvalidClientTokenId") }
    /// Indicates an incorrect combination of parameters, or a missing parameter. For example, trying to terminate an instance without specifying the instance ID.
    public static var invalidParameterCombination: AWSResponseError { .init(errorCode: "InvalidParameterCombination") }
    /// A value specified in a parameter is not valid, is unsupported, or cannot be used. Ensure that you specify a resource by using its full ID. The returned message provides an explanation of the error value.
    public static var invalidParameterValue: AWSResponseError { .init(errorCode: "InvalidParameterValue") }
    /// The AWS query string is malformed or does not adhere to AWS standards.
    public static var invalidQueryParameter: AWSResponseError { .init(errorCode: "InvalidQueryParameter") }
    /// Authorization signature is invalid.
    public static var invalidSignature: AWSResponseError { .init(errorCode: "InvalidSignature") }
    /// The query string contains a syntax error.
    public static var malformedQueryString: AWSResponseError { .init(errorCode: "MalformedQueryString") }
    /// The request is missing an action or a required parameter.
    public static var missingAction: AWSResponseError { .init(errorCode: "MissingAction") }
    /// The request must contain either a valid (registered) AWS access key ID or X.509 certificate.
    public static var missingAuthenticationToken: AWSResponseError { .init(errorCode: "MissingAuthenticationToken") }
    /// The request is missing a required parameter. Ensure that you have supplied all the required parameters for the request; for example, the resource ID.
    public static var missingParameter: AWSResponseError { .init(errorCode: "MissingParameter") }
    /// You are not authorized to use the requested service. Ensure that you have subscribed to the service you are trying to use. If you are new to AWS, your account might take some time to be activated while your credit card details are being verified.
    public static var optInRequired: AWSResponseError { .init(errorCode: "OptInRequired") }
    /// The request reached the service more than 15 minutes after the date stamp on the request or more than 15 minutes after the request expiration date (such as for pre-signed URLs), or the date stamp on the request is more than 15 minutes in the future. If you're using temporary security credentials, this error can also occur if the credentials have expired. For more information, see Temporary Security Credentials in the IAM User Guide.
    public static var requestExpired: AWSResponseError { .init(errorCode: "RequestExpired") }
    /// Authorization signature does not match the signature provided.
    public static var signatureDoesNotMatch: AWSResponseError { .init(errorCode: "SignatureDoesNotMatch") }
    /// The request was denied due to request throttling.
    public static var throttling: AWSResponseError { .init(errorCode: "Throttling") }
    /// AWS access key ID provided does not exist in our records.
    public static var unrecognizedClient: AWSResponseError { .init(errorCode: "UnrecognizedClient") }
    /// The input fails to satisfy the constraints specified by an AWS service.
    public static var validationError: AWSResponseError { .init(errorCode: "ValidationError") }
    /// The request processing has failed because of an unknown error, exception or failure.
    public static var internalFailure: AWSResponseError { .init(errorCode: "InternalFailure") }
    /// The request has failed due to a temporary failure of the server.
    public static var serviceUnavailable: AWSResponseError { .init(errorCode: "ServiceUnavailable") }
}

extension AWSResponseError: Equatable {
    public static func == (lhs: AWSResponseError, rhs: AWSResponseError) -> Bool {
        lhs.errorCode == rhs.errorCode
    }
}

extension AWSResponseError: CustomStringConvertible {
    public var description: String {
        "\(self.errorCode): \(message ?? "")"
    }
}
