#!/usr/bin/env swift sh
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

import Stencil  // soto-project/Stencil

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif

extension String {
    public func lowerFirst() -> String {
        String(self[startIndex]).lowercased() + self[index(after: startIndex)...]
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
    // list of errors comes from https://docs.aws.amazon.com/sns/latest/api/CommonErrors.html
    .init(name: "AccessDenied", description: "Access has been denied."),
    .init(name: "IncompleteSignature", description: "The request signature does not conform to AWS standards."),
    .init(name: "InvalidAction", description: "The action or operation requested is not valid. Verify that the action is typed correctly."),
    .init(name: "InvalidClientTokenId", description: "The X.509 certificate or AWS access key ID provided does not exist in our records."),
    .init(
        name: "InvalidParameterCombination",
        description:
            "Indicates an incorrect combination of parameters, or a missing parameter. For example, trying to terminate an instance without specifying the instance ID."
    ),
    .init(
        name: "InvalidParameterValue",
        description:
            "A value specified in a parameter is not valid, is unsupported, or cannot be used. Ensure that you specify a resource by using its full ID. The returned message provides an explanation of the error value."
    ),
    .init(name: "InvalidQueryParameter", description: "The AWS query string is malformed or does not adhere to AWS standards."),
    .init(name: "MalformedQueryString", description: "The query string contains a syntax error."),
    .init(name: "MissingAction", description: "The request is missing an action or a required parameter."),
    .init(
        name: "MissingAuthenticationToken",
        description: "The request must contain either a valid (registered) AWS access key ID or X.509 certificate."
    ),
    .init(
        name: "MissingParameter",
        description:
            "The request is missing a required parameter. Ensure that you have supplied all the required parameters for the request; for example, the resource ID."
    ),
    .init(
        name: "OptInRequired",
        description:
            "You are not authorized to use the requested service. Ensure that you have subscribed to the service you are trying to use. If you are new to AWS, your account might take some time to be activated while your credit card details are being verified."
    ),
    .init(
        name: "RequestExpired",
        description:
            "The request reached the service more than 15 minutes after the date stamp on the request or more than 15 minutes after the request expiration date (such as for pre-signed URLs), or the date stamp on the request is more than 15 minutes in the future. If you're using temporary security credentials, this error can also occur if the credentials have expired. For more information, see Temporary Security Credentials in the IAM User Guide."
    ),
    .init(name: "Throttling", description: "The request was denied due to request throttling."),
    .init(name: "ValidationError", description: "The input fails to satisfy the constraints specified by an AWS service."),
    // additional errors that are common across a number of services
    .init(name: "UnrecognizedClient", description: "AWS access key ID provided does not exist in our records."),
    .init(name: "InvalidSignature", description: "Authorization signature is invalid."),
    .init(name: "SignatureDoesNotMatch", description: "Authorization signature does not match the signature provided."),
]

let serverErrors: [Error] = [
    .init(name: "InternalFailure", description: "The request processing has failed because of an unknown error, exception or failure."),
    .init(name: "ServiceUnavailable", description: "The request has failed due to a temporary failure of the server."),
]

print("Loading templates")
let fsLoader = FileSystemLoader(paths: ["./scripts/templates/generate-errors"])
let environment = Environment(loader: fsLoader)

print("Creating ClientErrors.swift")

let clientErrorFile = try environment.renderTemplate(
    name: "generate-errors.stencil",
    context: ["name": "AWSClientError", "errors": clientErrors.sorted { $0.name < $1.name }]
)
try Data(clientErrorFile.utf8).write(to: URL(fileURLWithPath: "Sources/SotoCore/Errors/ClientErrors.swift"))

print("Creating ServerErrors.swift")

let serverErrorFile = try environment.renderTemplate(
    name: "generate-errors.stencil",
    context: ["name": "AWSServerError", "errors": serverErrors.sorted { $0.name < $1.name }]
)
try Data(serverErrorFile.utf8).write(to: URL(fileURLWithPath: "Sources/SotoCore/Errors/ServerErrors.swift"))
