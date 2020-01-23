//
//  AWSClient+Paginate.swift
//  AWSSDKSwift
//
//  Created by Adam Fowler on 2020/01/19.
//
//
import NIO

/// protocol for all AWSShapes that can be paginated.
/// Adds an initialiser that does a copy but inserts a new string based pagination token
public protocol AWSPaginateStringToken: AWSShape {
    func usingPaginationToken(_ token: String) -> Self
}

/// protocol for all AWSShapes that can be paginated.
/// Adds an initialiser that does a copy but inserts a new integer based pagination token
public protocol AWSPaginateIntToken: AWSShape {
    func usingPaginationToken(_ token: Int) -> Self
}

public extension AWSClient {
    
    /// If an AWS command is returning an arbituary sized array sometimes it adds support for paginating this array
    /// ie it will return the array in blocks of a defined size, each block also includes a token which can be used to access
    /// the next block. This function loads each block and calls a closure with each block as parameter.
    ///
    /// - Parameters:
    ///   - input: Input for request
    ///   - command: Command to be paginated
    ///   - resultKey: The keypath to the list of objects to be paginated
    ///   - tokenKey: The name of token in the response object to continue pagination
    ///   - onPage: closure called with each block of entries
    func paginate<Input: AWSPaginateStringToken, Output: AWSShape>(
        input: Input,
        command: @escaping (Input)->EventLoopFuture<Output>,
        tokenKey: KeyPath<Output, String?>,
        onPage: @escaping (Output, EventLoop)->EventLoopFuture<Bool>
    ) -> EventLoopFuture<Void> {
        let eventLoop = self.eventLoopGroup.next()
        let promise = eventLoop.makePromise(of: Void.self)

        func paginatePart(input: Input) {
            let responseFuture = command(input)
            responseFuture.whenSuccess { (response: Output)->Void in
                let onPageFuture = onPage(response, eventLoop)
                onPageFuture.whenSuccess { rt in
                    guard rt == true else { return promise.succeed(Void()) }
                    // get next block token and construct a new input with this token
                    guard let token = response[keyPath: tokenKey] else { return promise.succeed(Void()) }

                    let input = input.usingPaginationToken(token)
                    paginatePart(input: input)
                }
                onPageFuture.whenFailure { error in
                    promise.fail(error)
                }
            }
            responseFuture.whenFailure { error in
                promise.fail(error)
            }
        }

        paginatePart(input: input)
        
        return promise.futureResult
    }

    /// If an AWS command is returning an arbituary sized array sometimes it adds support for paginating this array
    /// ie it will return the array in blocks of a defined size, each block also includes a token which can be used to access
    /// the next block. This function loads each block and calls a closure with each block as parameter.
    ///
    /// This version uses an Int instead of a String for the token
    ///
    /// - Parameters:
    ///   - input: Input for request
    ///   - command: Command to be paginated
    ///   - resultKey: The keypath to the list of objects to be paginated
    ///   - tokenKey: The name of token in the response object to continue pagination
    ///   - onPage: closure called with each block of entries
    func paginate<Input: AWSPaginateIntToken, Output: AWSShape>(
        input: Input,
        command: @escaping (Input)->EventLoopFuture<Output>,
        tokenKey: KeyPath<Output, Int?>,
        onPage: @escaping (Output, EventLoop)->EventLoopFuture<Bool>
    ) -> EventLoopFuture<Void> {
        let eventLoop = self.eventLoopGroup.next()
        let promise = eventLoop.makePromise(of: Void.self)

        func paginatePart(input: Input) {
            let responseFuture = command(input)
            responseFuture.whenSuccess { (response: Output)->Void in
                let onPageFuture = onPage(response, eventLoop)
                onPageFuture.whenSuccess { rt in
                    guard rt == true else { return promise.succeed(Void()) }
                    // get next block token and construct a new input with this token
                    guard let token = response[keyPath: tokenKey] else { return promise.succeed(Void()) }

                    let input = input.usingPaginationToken(token)
                    paginatePart(input: input)
                }
                onPageFuture.whenFailure { error in
                    promise.fail(error)
                }
            }
            responseFuture.whenFailure { error in
                promise.fail(error)
            }
        }

        paginatePart(input: input)
        
        return promise.futureResult
    }
}

