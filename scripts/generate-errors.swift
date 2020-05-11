#!/usr/bin/env swift sh
//===----------------------------------------------------------------------===//
//
// This source file is part of the AWSSDKSwift open source project
//
// Copyright (c) 2017-2020 the AWSSDKSwift project authors
// Licensed under Apache License v2.0
//
// See LICENSE.txt for license information
// See CONTRIBUTORS.txt for the list of AWSSDKSwift project authors
//
// SPDX-License-Identifier: Apache-2.0
//
//===----------------------------------------------------------------------===//

import Foundation
import Stencil                  // swift-aws/Stencil

extension String {
    public func lowerFirst() -> String {
        return String(self[startIndex]).lowercased() + self[index(after: startIndex)...]
    }
}
    
struct Error {
    let name: String
    let description: String
    let `enum`: String
    
    init(name: String, description: String) {
        self.name = name
        self.description = description
        self.enum = name.lowerFirst()
    }
}

let clientErrors: [Error] = [
    .init(name: "AuthFailure", description: "The provided credentials could not be validated. Ensure that you are using the correct access keys."),
    .init(name: "Blocked", description: "Your account is currently blocked. Contact aws-verification@amazon.com if you have questions."),
    .init(name: "DryRunOperation", description: "The user has the required permissions, so the request would have succeeded, but the DryRun parameter was used."),
    .init(name: "IdempotentParameterMismatch", description: "The request uses the same client token as a previous, but non-identical request. Do not reuse a client token with different requests, unless the requests are identical."),
    .init(name: "IncompleteSignature", description: "The request signature does not conform to AWS standards."),
    .init(name: "InvalidAction", description: "The action or operation requested is not valid. Verify that the action is typed correctly."),
    .init(name: "InvalidCharacter", description: "A specified character is invalid."),
    .init(name: "InvalidClientTokenId", description: "The X.509 certificate or AWS access key ID provided does not exist in our records."),
    .init(name: "InvalidPaginationToken", description: "The specified pagination token is not valid or is expired."),
    .init(name: "InvalidParameter", description: "A parameter specified in a request is not valid, is unsupported, or cannot be used. The returned message provides an explanation of the error value."),
    .init(name: "InvalidParameterCombination", description: "Indicates an incorrect combination of parameters, or a missing parameter. For example, trying to terminate an instance without specifying the instance ID."),
    .init(name: "InvalidParameterValue", description: "A value specified in a parameter is not valid, is unsupported, or cannot be used. Ensure that you specify a resource by using its full ID. The returned message provides an explanation of the error value."),
    .init(name: "InvalidQueryParameter", description: "The AWS query string is malformed or does not adhere to AWS standards."),
    .init(name: "InvalidSignature", description: "The request signature we calculated does not match the signature you provided. Check your AWS secret access key and signing method. For more information, see REST Authentication and SOAP Authentication for details."),
    .init(name: "MalformedQueryString", description: "The query string contains a syntax error."),
    .init(name: "MissingAction", description: "The request is missing an action or a required parameter."),
    .init(name: "MissingAuthenticationToken", description: "The request must contain either a valid (registered) AWS access key ID or X.509 certificate."),
    .init(name: "MissingParameter", description: "The request is missing a required parameter. Ensure that you have supplied all the required parameters for the request; for example, the resource ID."),
    .init(name: "OptInRequired", description: "You are not authorized to use the requested service. Ensure that you have subscribed to the service you are trying to use. If you are new to AWS, your account might take some time to be activated while your credit card details are being verified."),
    .init(name: "PendingVerification", description: "Your account is pending verification. Until the verification process is complete, you may not be able to carry out requests with this account. If you have questions, contact AWS Support."),
    .init(name: "RequestExpired", description: "The request reached the service more than 15 minutes after the date stamp on the request or more than 15 minutes after the request expiration date (such as for pre-signed URLs), or the date stamp on the request is more than 15 minutes in the future. If you're using temporary security credentials, this error can also occur if the credentials have expired. For more information, see Temporary Security Credentials in the IAM User Guide."),
    .init(name: "UnauthorizedOperation", description: "You are not authorized to perform this operation. Check your IAM policies, and ensure that you are using the correct access keys. For more information, see Controlling Access. If the returned message is encoded, you can decode it using the DecodeAuthorizationMessage action. For more information, see DecodeAuthorizationMessage in the AWS Security Token Service API Reference."),
    .init(name: "UnknownParameter", description: "An unknown or unrecognized parameter was supplied. Requests that could cause this error include supplying a misspelled parameter or a parameter that is not supported for the specified API version."),
    .init(name: "UnsupportedInstanceAttribute", description: "The specified attribute cannot be modified."),
    .init(name: "UnsupportedOperation", description: "The specified request includes an unsupported operation. For example, you can't stop an instance that's instance store-backed. Or you might be trying to launch an instance type that is not supported by the specified AMI. The returned message provides details of the unsupported operation."),
    .init(name: "UnsupportedProtocol", description: "SOAP has been deprecated and is no longer supported. For more information, see SOAP Requests."),
    .init(name: "ValidationError", description: "The input fails to satisfy the constraints specified by an AWS service."),
    .init(name: "AccessDenied", description: "Access has been denied."),
    .init(name: "SignatureDoesNotMatch", description: "The request signature we calculated does not match the signature you provided. Check your AWS secret access key and signing method. For more information, see REST Authentication and SOAP Authentication for details."),
]

let serverErrors: [Error] = [
    .init(name: "InsufficientAddressCapacity", description: "Not enough available addresses to satisfy your minimum request. Reduce the number of addresses you are requesting or wait for additional capacity to become available."),
    .init(name: "InsufficientCapacity", description: "There is not enough capacity to fulfill your import instance request. You can wait for additional capacity to become available."),
    .init(name: "InsufficientInstanceCapacity", description: "There is not enough capacity to fulfill your instance request. Reduce the number of instances in your request, or wait for additional capacity to become available. You can also try launching an instance by selecting different instance types (which you can resize at a later stage). The returned message might also give specific guidance about how to solve the problem."),
    .init(name: "InsufficientHostCapacity", description: "There is not enough capacity to fulfill your Dedicated Host request. Reduce the number of Dedicated Hosts in your request, or wait for additional capacity to become available."),
    .init(name: "InsufficientReservedInstanceCapacity", description: "Not enough available Reserved instances to satisfy your minimum request. Reduce the number of Reserved instances in your request or wait for additional capacity to become available."),
    .init(name: "InternalError", description: "An internal error has occurred. Retry your request, but if the problem persists, contact us with details by posting a message on the AWS forums."),
    .init(name: "InternalFailure", description: "The request processing has failed because of an unknown error, exception or failure."),
    .init(name: "RequestLimitExceeded", description: "The maximum request rate permitted by the Amazon EC2 APIs has been exceeded for your account. For best results, use an increasing or variable sleep interval between requests. For more information, see Query API Request Rate."),
    .init(name: "ServiceUnavailable", description: "The request has failed due to a temporary failure of the server."),
    .init(name: "Unavailable", description: "The server is overloaded and can't handle the request."),
]
    
print("Loading templates")
let fsLoader = FileSystemLoader(paths: ["./scripts/templates/generate-errors"])
let environment = Environment(loader: fsLoader)

print("Creating ClientErrors.swift")

let clientErrorFile = try environment.renderTemplate(name: "generate-errors.stencil", context: ["name": "AWSClientError", "errors": clientErrors.sorted { $0.name < $1.name }])
try Data(clientErrorFile.utf8).write(to: URL(fileURLWithPath: "Sources/AWSSDKSwiftCore/Errors/ClientErrors.swift"))

print("Creating ServerErrors.swift")

let serverErrorFile = try environment.renderTemplate(name: "generate-errors.stencil", context: ["name": "AWSServerError", "errors": serverErrors.sorted { $0.name < $1.name }])
try Data(serverErrorFile.utf8).write(to: URL(fileURLWithPath: "Sources/AWSSDKSwiftCore/Errors/ServerErrors.swift"))

