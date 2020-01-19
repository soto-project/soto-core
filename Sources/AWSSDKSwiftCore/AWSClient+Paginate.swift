//
//  AWSClient+Paginate.swift
//  AWSSDKSwift
//
//  Created by Adam Fowler on 2020/01/19.
//
//
import NIO

/// protocol for all AWSShapes that can be paginated.
/// Adds an initialiser that does a copy but inserts a new pagination token
protocol AWSPaginateable: AWSShape {
    init(_ original: Self, token: String)
}

extension AWSClient {
    func paginate<Input: AWSPaginateable, Output: AWSShape, PaginateOutput: AWSShape>(input: Input, command: @escaping (Input)->EventLoopFuture<FullOutput>, contentsKey: String, tokenKey: String) -> Future<[PaginateOutput]> {
        var list : [PaginateOutput] = []
        
        func paginatePart(input: Input) -> Future<[PaginateOutput]> {
            let objects = command(input).flatMap { (response: Output) -> Future<[PaginateOutput]> in
                let mirror = Mirror(reflecting: response)
                guard let contents = mirror.getAttribute(forKey: contentsKey) as? [PaginateOutput] else { return self.eventLoopGroup.next().makeSucceededFuture(list) }

                list.append(contentsOf: contents)

                guard let token = mirror.getAttribute(forKey: tokenKey) as? String else { return self.eventLoopGroup.next().makeSucceededFuture(list) }

                let input = Input.init(input, token: token)
                return paginatePart(input: input)
            }
            return objects
        }
        return paginatePart(input: input)
    }
}

