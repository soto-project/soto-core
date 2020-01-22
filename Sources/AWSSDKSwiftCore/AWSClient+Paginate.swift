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
    init(_ original: Self, token: String)
}

/// protocol for all AWSShapes that can be paginated.
/// Adds an initialiser that does a copy but inserts a new integer based pagination token
public protocol AWSPaginateIntToken: AWSShape {
    init(_ original: Self, token: Int)
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
    func paginate<Input: AWSPaginateStringToken, Output: AWSShape, Result>(
        input: Input,
        command: @escaping (Input)->EventLoopFuture<Output>,
        resultKey: PartialKeyPath<Output>,
        tokenKey: KeyPath<Output, String?>,
        onPage: @escaping ([Result], EventLoop)->EventLoopFuture<Bool>
    ) -> EventLoopFuture<Void> {
        let eventLoop = self.eventLoopGroup.next()
        let promise = eventLoop.makePromise(of: Void.self)

        func paginatePart(input: Input) {
            let responseFuture = command(input)
            responseFuture.whenSuccess { (response: Output)->Void in
                // extract results from response and add to list
                let results = response[keyPath: resultKey] as? [Result] ?? []

                let onPageFuture = onPage(results, eventLoop)
                onPageFuture.whenSuccess { rt in
                    guard rt == true else { return promise.succeed(Void()) }
                    // get next block token and construct a new input with this token
                    guard let token = response[keyPath: tokenKey] else { return promise.succeed(Void()) }

                    let input = Input.init(input, token: token)
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
    /// This version returns two arrays
    ///
    /// - Parameters:
    ///   - input: Input for request
    ///   - command: Command to be paginated
    ///   - resultKey1: The keypath to the first list of objects to be paginated
    ///   - resultKey2: The keypath to the second list of objects to be paginated
    ///   - tokenKey: The name of token in the response object to continue pagination
    ///   - onPage: closure called with each block of entries
    func paginate<Input: AWSPaginateStringToken, Output: AWSShape, Result1, Result2>(
        input: Input,
        command: @escaping (Input)->EventLoopFuture<Output>,
        resultKey1: PartialKeyPath<Output>,
        resultKey2: PartialKeyPath<Output>,
        tokenKey: KeyPath<Output, String?>,
        onPage: @escaping ([Result1], [Result2], EventLoop)->EventLoopFuture<Bool>
    ) -> EventLoopFuture<Void> {
        let eventLoop = self.eventLoopGroup.next()
        let promise = eventLoop.makePromise(of: Void.self)

        func paginatePart(input: Input) {
            let responseFuture = command(input)
            responseFuture.whenSuccess { (response: Output)->Void in
                // extract results from response and add to list
                let results1 = response[keyPath: resultKey1] as? [Result1] ?? []
                let results2 = response[keyPath: resultKey2] as? [Result2] ?? []

                let onPageFuture = onPage(results1, results2, eventLoop)
                onPageFuture.whenSuccess { rt in
                    guard rt == true else { return promise.succeed(Void()) }
                    // get next block token and construct a new input with this token
                    guard let token = response[keyPath: tokenKey] else { return promise.succeed(Void()) }

                    let input = Input.init(input, token: token)
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
    /// This version returns three arrays
    ///
    /// - Parameters:
    ///   - input: Input for request
    ///   - command: Command to be paginated
    ///   - resultKey1: The keypath to the first list of objects to be paginated
    ///   - resultKey2: The keypath to the second list of objects to be paginated
    ///   - resultKey3: The keypath to the third list of objects to be paginated
    ///   - tokenKey: The name of token in the response object to continue pagination
    ///   - onPage: closure called with each block of entries
    func paginate<Input: AWSPaginateStringToken, Output: AWSShape, Result1, Result2, Result3>(
        input: Input,
        command: @escaping (Input)->EventLoopFuture<Output>,
        resultKey1: PartialKeyPath<Output>,
        resultKey2: PartialKeyPath<Output>,
        resultKey3: PartialKeyPath<Output>,
        tokenKey: KeyPath<Output, String?>,
        onPage: @escaping ([Result1], [Result2], [Result3], EventLoop)->EventLoopFuture<Bool>
    ) -> EventLoopFuture<Void> {
        let eventLoop = self.eventLoopGroup.next()
        let promise = eventLoop.makePromise(of: Void.self)

        func paginatePart(input: Input) {
            let responseFuture = command(input)
            responseFuture.whenSuccess { (response: Output)->Void in
                // extract results from response and add to list
                let results1 = response[keyPath: resultKey1] as? [Result1] ?? []
                let results2 = response[keyPath: resultKey2] as? [Result2] ?? []
                let results3 = response[keyPath: resultKey3] as? [Result3] ?? []

                let onPageFuture = onPage(results1, results2, results3, eventLoop)
                onPageFuture.whenSuccess { rt in
                    guard rt == true else { return promise.succeed(Void()) }
                    // get next block token and construct a new input with this token
                    guard let token = response[keyPath: tokenKey] else { return promise.succeed(Void()) }

                    let input = Input.init(input, token: token)
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
    /// This version returns four arrays
    ///
    /// - Parameters:
    ///   - input: Input for request
    ///   - command: Command to be paginated
    ///   - resultKey1: The keypath to the first list of objects to be paginated
    ///   - resultKey2: The keypath to the second list of objects to be paginated
    ///   - resultKey3: The keypath to the third list of objects to be paginated
    ///   - resultKey4: The keypath to the fourth list of objects to be paginated
    ///   - tokenKey: The name of token in the response object to continue pagination
    ///   - onPage: closure called with each block of entries
    func paginate<Input: AWSPaginateStringToken, Output: AWSShape, Result1, Result2, Result3, Result4>(
        input: Input,
        command: @escaping (Input)->EventLoopFuture<Output>,
        resultKey1: PartialKeyPath<Output>,
        resultKey2: PartialKeyPath<Output>,
        resultKey3: PartialKeyPath<Output>,
        resultKey4: PartialKeyPath<Output>,
        tokenKey: KeyPath<Output, String?>,
        onPage: @escaping ([Result1], [Result2], [Result3], [Result4], EventLoop)->EventLoopFuture<Bool>
    ) -> EventLoopFuture<Void> {
        let eventLoop = self.eventLoopGroup.next()
        let promise = eventLoop.makePromise(of: Void.self)

        func paginatePart(input: Input) {
            let responseFuture = command(input)
            responseFuture.whenSuccess { (response: Output)->Void in
                // extract results from response and add to list
                let results1 = response[keyPath: resultKey1] as? [Result1] ?? []
                let results2 = response[keyPath: resultKey2] as? [Result2] ?? []
                let results3 = response[keyPath: resultKey3] as? [Result3] ?? []
                let results4 = response[keyPath: resultKey4] as? [Result4] ?? []

                let onPageFuture = onPage(results1, results2, results3, results4, eventLoop)
                onPageFuture.whenSuccess { rt in
                    guard rt == true else { return promise.succeed(Void()) }
                    // get next block token and construct a new input with this token
                    guard let token = response[keyPath: tokenKey] else { return promise.succeed(Void()) }

                    let input = Input.init(input, token: token)
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
    func paginate<Input: AWSPaginateIntToken, Output: AWSShape, Result>(
        input: Input,
        command: @escaping (Input)->EventLoopFuture<Output>,
        resultKey: PartialKeyPath<Output>,
        tokenKey: KeyPath<Output, Int?>,
        onPage: @escaping ([Result], EventLoop)->EventLoopFuture<Bool>
    ) -> EventLoopFuture<Void> {
        let eventLoop = self.eventLoopGroup.next()
        let promise = eventLoop.makePromise(of: Void.self)

        func paginatePart(input: Input) {
            let responseFuture = command(input)
            responseFuture.whenSuccess { (response: Output)->Void in
                // extract results from response and add to list
                let results = response[keyPath: resultKey] as? [Result] ?? []

                let onPageFuture = onPage(results, eventLoop)
                onPageFuture.whenSuccess { rt in
                    guard rt == true else { return promise.succeed(Void()) }
                    // get next block token and construct a new input with this token
                    guard let token = response[keyPath: tokenKey] else { return promise.succeed(Void()) }

                    let input = Input.init(input, token: token)
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

