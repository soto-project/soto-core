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
public protocol AWSPaginateStringToken: AWSShape {
    init(_ original: Self, token: String)
}

public protocol AWSPaginateIntToken: AWSShape {
    init(_ original: Self, token: Int)
}

public extension AWSClient {
    /// If an AWS command is returning an arbituary sized array sometimes it adds support for paginating this array
    /// ie it will return the array in blocks of a defined size, each block also includes a token which can be used to access
    /// the next block. This function returns a future that will contain the full contents of the array.
    ///
    /// - Parameters:
    ///   - input: Input for request
    ///   - command: Command to be paginated
    ///   - resultKey: The name of the objects to be paginated in the response object
    ///   - tokenKey: The name of token in the response object to continue pagination
    func paginate<Input: AWSPaginateStringToken, Output: AWSShape, PaginateOutput>(input: Input, command: @escaping (Input)->EventLoopFuture<Output>, resultKey: String, tokenKey: String) -> EventLoopFuture<[PaginateOutput]> {
        var list : [PaginateOutput] = []
        
        func paginatePart(input: Input) -> EventLoopFuture<[PaginateOutput]> {
            let objects = command(input).flatMap { (response: Output) -> EventLoopFuture<[PaginateOutput]> in
                // extract results from response and add to list
                let mirror = Mirror(reflecting: response)
                guard let results = mirror.getAttribute(forKey: resultKey) as? [PaginateOutput] else { return self.eventLoopGroup.next().makeSucceededFuture(list) }
                list.append(contentsOf: results)

                // get next block token and construct a new input with this token
                guard let token = mirror.getAttribute(forKey: tokenKey) as? String else { return self.eventLoopGroup.next().makeSucceededFuture(list) }
                let input = Input.init(input, token: token)

                return paginatePart(input: input)
            }
            return objects
        }
        return paginatePart(input: input)
    }


    /// If an AWS command is returning an arbituary sized array sometimes it adds support for paginating this array
    /// ie it will return the array in blocks of a defined size, each block also includes a token which can be used to access
    /// the next block. This function returns a future that will contain the full contents of the array.
    ///
    /// - Parameters:
    ///   - input: Input for request
    ///   - command: Command to be paginated
    ///   - resultKey: The name of the objects to be paginated in the response object
    ///   - tokenKey: The name of token in the response object to continue pagination
    func paginate<Input: AWSPaginateIntToken, Output: AWSShape, PaginateOutput>(input: Input, command: @escaping (Input)->EventLoopFuture<Output>, resultKey: String, tokenKey: String) -> EventLoopFuture<[PaginateOutput]> {
        var list : [PaginateOutput] = []
        
        func paginatePart(input: Input) -> EventLoopFuture<[PaginateOutput]> {
            let objects = command(input).flatMap { (response: Output) -> EventLoopFuture<[PaginateOutput]> in
                // extract results from response and add to list
                let mirror = Mirror(reflecting: response)
                guard let results = mirror.getAttribute(forKey: resultKey) as? [PaginateOutput] else { return self.eventLoopGroup.next().makeSucceededFuture(list) }
                list.append(contentsOf: results)

                // get next block token and construct a new input with this token
                guard let token = mirror.getAttribute(forKey: tokenKey) as? Int else { return self.eventLoopGroup.next().makeSucceededFuture(list) }
                let input = Input.init(input, token: token)

                return paginatePart(input: input)
            }
            return objects
        }
        return paginatePart(input: input)
    }
}

