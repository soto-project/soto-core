import HypertextApplicationLanguage
import Foundation

extension AWSClient {
    /// process hal+json date. Extract properties from HAL
    func hypertextApplicationLanguageProcess(response: AWSResponse, members: [AWSShapeMember]) throws -> AWSResponse {
        guard case .json(let data) = response.body,
            let contentType = response.headers["Content-Type"] as? String,
            contentType.contains("hal+json") else {
                return response
        }
        
        let representation = try Representation.from(json: data)
        var dictionary = representation.properties
        for rel in representation.rels {
            guard let representations = representation.representations(for: rel) else {
                continue
            }

            // get member type hint
            guard let hint = members.filter({ $0.location?.name == rel }).first else {
                continue
            }

            switch hint.type {
            case .list:
                dictionary[rel] = representations.map({ $0.properties })

            default:
                dictionary[rel] = representations.map({ $0.properties }).first
            }
        }
        var response = response
        response.body = .json(try JSONSerialization.data(withJSONObject: dictionary, options: []))
        return response
    }
}
