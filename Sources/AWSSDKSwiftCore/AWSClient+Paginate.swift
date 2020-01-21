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
    func paginate<Input: AWSPaginateStringToken, Output: AWSShape, Result>(input: Input, command: @escaping (Input)->EventLoopFuture<Output>, resultKey: PartialKeyPath<Output>, tokenKey: KeyPath<Output, String?>, onPage: @escaping ([Result], EventLoop)->EventLoopFuture<Bool>) -> EventLoopFuture<Void> {
        
        func paginatePart(input: Input) -> EventLoopFuture<Void> {
            let future = command(input).flatMap { (response: Output) -> EventLoopFuture<Void> in
                // extract results from response and add to list
                let results = response[keyPath: resultKey] as? [Result] ?? []
                
                return onPage(results, self.eventLoopGroup.next()).flatMap { rt in
                    guard rt == true else { return self.eventLoopGroup.next().makeSucceededFuture(Void()) }
                    // get next block token and construct a new input with this token
                    guard let token = response[keyPath: tokenKey] else { return self.eventLoopGroup.next().makeSucceededFuture(Void()) }
                    let input = Input.init(input, token: token)
                    return paginatePart(input: input)
                }
            }
            return future
        }
        return paginatePart(input: input)
    }

    /// If an AWS command is returning an arbituary sized array sometimes it adds support for paginating this array
    /// ie it will return the array in blocks of a defined size, each block also includes a token which can be used to access
    /// the next block. This function returns a future that will contain the full contents of the array.
    ///
    /// This version returns two arrays
    ///
    /// - Parameters:
    ///   - input: Input for request
    ///   - command: Command to be paginated
    ///   - resultKey1: The name of the first set of objects to be paginated in the response object
    ///   - resultKey2: The name of the second set of objects to be paginated in the response object
    ///   - tokenKey: The name of token in the response object to continue pagination
    func paginate<Input: AWSPaginateStringToken, Output: AWSShape, Result1, Result2>(input: Input, command: @escaping (Input)->EventLoopFuture<Output>, resultKey1: PartialKeyPath<Output>, resultKey2: PartialKeyPath<Output>, tokenKey: KeyPath<Output, String?>, onPage: @escaping ([Result1], [Result2], EventLoop)->EventLoopFuture<Bool>) -> EventLoopFuture<Void> {

        func paginatePart(input: Input) -> EventLoopFuture<Void> {
            let objects = command(input).flatMap { (response: Output) -> EventLoopFuture<Void> in
                // extract results from response and add to list
                let results1 = response[keyPath: resultKey1] as? [Result1] ?? []
                let results2 = response[keyPath: resultKey2] as? [Result2] ?? []

                 return onPage(results1, results2, self.eventLoopGroup.next()).flatMap { rt in
                    guard rt == true else { return self.eventLoopGroup.next().makeSucceededFuture(Void()) }
                    // get next block token and construct a new input with this token
                    guard let token = response[keyPath: tokenKey] else { return self.eventLoopGroup.next().makeSucceededFuture(Void()) }
                    let input = Input.init(input, token: token)
                    return paginatePart(input: input)
                }
           }
            return objects
        }
        return paginatePart(input: input)
    }

    /// If an AWS command is returning an arbituary sized array sometimes it adds support for paginating this array
    /// ie it will return the array in blocks of a defined size, each block also includes a token which can be used to access
    /// the next block. This function returns a future that will contain the full contents of the array.
    ///
    /// This version returns three arrays
    ///
    /// - Parameters:
    ///   - input: Input for request
    ///   - command: Command to be paginated
    ///   - resultKey1: The name of the first set of objects to be paginated in the response object
    ///   - resultKey2: The name of the second set of objects to be paginated in the response object
    ///   - resultKey3: The name of the second set of objects to be paginated in the response object
    ///   - tokenKey: The name of token in the response object to continue pagination
    func paginate<Input: AWSPaginateStringToken, Output: AWSShape, Result1, Result2, Result3>(input: Input, command: @escaping (Input)->EventLoopFuture<Output>, resultKey1: PartialKeyPath<Output>, resultKey2: PartialKeyPath<Output>, resultKey3: PartialKeyPath<Output>, tokenKey: KeyPath<Output, String?>, onPage: @escaping ([Result1], [Result2], [Result3], EventLoop)->EventLoopFuture<Bool>) -> EventLoopFuture<Void> {

        func paginatePart(input: Input) -> EventLoopFuture<Void> {
            let objects = command(input).flatMap { (response: Output) -> EventLoopFuture<Void> in
                // extract results from response and add to list
                let results1 = response[keyPath: resultKey1] as? [Result1] ?? []
                let results2 = response[keyPath: resultKey2] as? [Result2] ?? []
                let results3 = response[keyPath: resultKey3] as? [Result3] ?? []

                return onPage(results1, results2, results3, self.eventLoopGroup.next()).flatMap { rt in
                    guard rt == true else { return self.eventLoopGroup.next().makeSucceededFuture(Void()) }
                    // get next block token and construct a new input with this token
                    guard let token = response[keyPath: tokenKey] else { return self.eventLoopGroup.next().makeSucceededFuture(Void()) }
                    let input = Input.init(input, token: token)
                    return paginatePart(input: input)
                }
            }
            return objects
        }
        return paginatePart(input: input)
    }

    /// If an AWS command is returning an arbituary sized array sometimes it adds support for paginating this array
    /// ie it will return the array in blocks of a defined size, each block also includes a token which can be used to access
    /// the next block. This function returns a future that will contain the full contents of the array.
    ///
    /// This version returns four arrays
    ///
    /// - Parameters:
    ///   - input: Input for request
    ///   - command: Command to be paginated
    ///   - resultKey1: The name of the first set of objects to be paginated in the response object
    ///   - resultKey2: The name of the second set of objects to be paginated in the response object
    ///   - resultKey3: The name of the second set of objects to be paginated in the response object
    ///   - tokenKey: The name of token in the response object to continue pagination
    func paginate<Input: AWSPaginateStringToken, Output: AWSShape, Result1, Result2, Result3, Result4>(input: Input, command: @escaping (Input)->EventLoopFuture<Output>, resultKey1: PartialKeyPath<Output>, resultKey2: PartialKeyPath<Output>, resultKey3: PartialKeyPath<Output>, resultKey4: PartialKeyPath<Output>, tokenKey: KeyPath<Output, String?>, onPage: @escaping ([Result1], [Result2], [Result3], [Result4], EventLoop)->EventLoopFuture<Bool>) -> EventLoopFuture<Void> {

        func paginatePart(input: Input) -> EventLoopFuture<Void> {
            let objects = command(input).flatMap { (response: Output) -> EventLoopFuture<Void> in
                // extract results from response and add to list
                let results1 = response[keyPath: resultKey1] as? [Result1] ?? []
                let results2 = response[keyPath: resultKey2] as? [Result2] ?? []
                let results3 = response[keyPath: resultKey3] as? [Result3] ?? []
                let results4 = response[keyPath: resultKey4] as? [Result4] ?? []

                 return onPage(results1, results2, results3, results4, self.eventLoopGroup.next()).flatMap { rt in
                    guard rt == true else { return self.eventLoopGroup.next().makeSucceededFuture(Void()) }
                    // get next block token and construct a new input with this token
                    guard let token = response[keyPath: tokenKey] else { return self.eventLoopGroup.next().makeSucceededFuture(Void()) }
                    let input = Input.init(input, token: token)
                    return paginatePart(input: input)
                }
            }
            return objects
        }
        return paginatePart(input: input)
    }

    /// If an AWS command is returning an arbituary sized array sometimes it adds support for paginating this array
    /// ie it will return the array in blocks of a defined size, each block also includes a token which can be used to access
    /// the next block. This function returns a future that will contain the full contents of the array.
    ///
    /// This version uses an Int instead of a String for the token
    ///
    /// - Parameters:
    ///   - input: Input for request
    ///   - command: Command to be paginated
    ///   - resultKey: The name of the objects to be paginated in the response object
    ///   - tokenKey: The name of token in the response object to continue pagination
    func paginate<Input: AWSPaginateIntToken, Output: AWSShape, Result>(input: Input, command: @escaping (Input)->EventLoopFuture<Output>, resultKey: PartialKeyPath<Output>, tokenKey: KeyPath<Output, Int?>, onPage: @escaping ([Result], EventLoop)->EventLoopFuture<Bool>) -> EventLoopFuture<Void> {
        
        func paginatePart(input: Input) -> EventLoopFuture<Void> {
            let future = command(input).flatMap { (response: Output) -> EventLoopFuture<Void> in
                // extract results from response and add to list
                // extract results from response and add to list
                let results = response[keyPath: resultKey] as? [Result] ?? []
                
                return onPage(results, self.eventLoopGroup.next()).flatMap { rt in
                    guard rt == true else { return self.eventLoopGroup.next().makeSucceededFuture(Void()) }
                    // get next block token and construct a new input with this token
                    guard let token = response[keyPath: tokenKey] else { return self.eventLoopGroup.next().makeSucceededFuture(Void()) }
                    let input = Input.init(input, token: token)
                    return paginatePart(input: input)
                }
            }
            return future
        }
        return paginatePart(input: input)
    }
}

