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

import class Foundation.JSONSerialization
import NIO

// AWS HAL services I know of are APIGateway, Pinpoint, Greengrass
extension AWSResponse {
    /// process hal+json date. Extract properties from HAL
    func getHypertextApplicationLanguageBody() throws -> Body {
        guard case .json(let buffer) = self.body,
            let contentType = self.headers["content-type"] as? String,
            contentType.contains("hal+json")
        else {
            return false
        }
        return true
    }

    /// process hal+json data. Extract properties from HAL
    func getHypertextApplicationLanguageDictionary() throws -> [String: Any] {
        guard case .json(let buffer) = self.body else { return [:] }
        // extract embedded resources from HAL
        guard let data = buffer.getData(at: buffer.readerIndex, length: buffer.readableBytes) else { return self.body }
        let json = try JSONSerialization.jsonObject(with: data, options: [])
        guard var dictionary = json as? [String: Any],
            let embedded = dictionary["_embedded"],
            let embeddedDictionary = embedded as? [String: Any]
        else {
            return dictionary
        }

        // remove _links and _embedded elements of dictionary to reduce the size of the new dictionary
        dictionary["_links"] = nil
        dictionary["_embedded"] = nil
        // merge embedded resources into original dictionary
        dictionary.merge(embeddedDictionary) { first, _ in return first }
        let jsonData = try JSONSerialization.data(withJSONObject: dictionary, options: [])
        return .json(ByteBufferAllocator().buffer(data: jsonData))
    }
}
