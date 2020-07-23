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

import AsyncHTTPClient
import NIO
import XCTest
import AWSTestUtils
@testable import AWSSDKSwiftCore

class PaginateTests: XCTestCase {
    enum Error: Swift.Error {
        case didntFindToken
    }
    var awsServer: AWSTestServer!
    var eventLoopGroup: EventLoopGroup!
    var httpClient: AWSHTTPClient!
    var client: AWSClient!
    var config: AWSServiceConfig!

    override func setUp() {
        // create server and client
        awsServer = AWSTestServer(serviceProtocol: .json)
        eventLoopGroup = MultiThreadedEventLoopGroup(numberOfThreads: 3)
        httpClient = AsyncHTTPClient.HTTPClient(eventLoopGroupProvider: .shared(eventLoopGroup))
        config = createServiceConfig(serviceProtocol: .json(version: "1.1"), endpoint: awsServer.address)
        client = createAWSClient(credentialProvider: .empty, retryPolicy: .noRetry, httpClientProvider: .shared(httpClient))
    }

    override func tearDown() {
        XCTAssertNoThrow(try self.awsServer.stop())
        XCTAssertNoThrow(try self.client.syncShutdown())
        XCTAssertNoThrow(try self.httpClient.syncShutdown())
        XCTAssertNoThrow(try self.eventLoopGroup.syncShutdownGracefully())
    }

    // test structures/functions
    struct CounterInput: AWSEncodableShape, AWSPaginateToken, Decodable {
        let inputToken: Int?
        let pageSize: Int

        init(inputToken: Int?, pageSize: Int) {
            self.inputToken = inputToken
            self.pageSize = pageSize
        }

        func usingPaginationToken(_ token: Int) -> CounterInput {
            return .init(inputToken: token, pageSize: self.pageSize)
        }
    }
    // conform to Encodable so server can encode these
    struct CounterOutput: AWSDecodableShape, Encodable {
        let array: [Int]
        let outputToken: Int?
    }

    func counter(_ input: CounterInput, on eventLoop: EventLoop?, logger: Logger) -> EventLoopFuture<CounterOutput> {
        return client.execute(
            operation: "TestOperation",
            path: "/",
            httpMethod: .POST,
            serviceConfig: config,
            input: input,
            on: eventLoop,
            logger: logger
        )
    }

    func counterPaginator(_ input: CounterInput, onPage: @escaping (CounterOutput, EventLoop)->EventLoopFuture<Bool>) -> EventLoopFuture<Void> {
        return client.paginate(input: input, command: counter, tokenKey: \CounterOutput.outputToken, onPage: onPage)
    }

    func testIntegerTokenPaginate() throws {

        // paginate input
        var finalArray: [Int] = []
        let input = CounterInput(inputToken: nil, pageSize: 4)
        let future = counterPaginator(input) { result, eventloop in
            // collate results into array
            finalArray.append(contentsOf: result.array)
            return eventloop.makeSucceededFuture(true)
        }

        let arraySize = 23
        // aws server process
        XCTAssertNoThrow(try awsServer.process { (input: CounterInput) throws -> AWSTestServer.Result<CounterOutput> in
            // send part of array of numbers based on input startIndex and pageSize
            let startIndex = input.inputToken ?? 0
            let endIndex = min(startIndex+input.pageSize, arraySize)
            var array: [Int] = []
            for i in startIndex..<endIndex {
                array.append(i)
            }
            let continueProcessing = (endIndex != arraySize)
            let output = CounterOutput(array: array, outputToken: endIndex != arraySize ? endIndex : nil)
            return .result(output, continueProcessing: continueProcessing)
        })

        // wait for response
        XCTAssertNoThrow(try future.wait())

        // verify contents of array
        XCTAssertEqual(finalArray.count, arraySize)
        for i in 0..<finalArray.count {
            XCTAssertEqual(finalArray[i], i)
        }
    }

    // test structures/functions
    struct StringListInput: AWSEncodableShape, AWSPaginateToken, Decodable {
        let inputToken: String?
        let pageSize: Int

        init(inputToken: String?, pageSize: Int) {
            self.inputToken = inputToken
            self.pageSize = pageSize
        }

        func usingPaginationToken(_ token: String) -> StringListInput {
            return .init(inputToken: token, pageSize: self.pageSize)
        }
    }
    // conform to Encodable so server can encode these
    struct StringListOutput: AWSDecodableShape, Encodable {
        let array: [String]
        let outputToken: String?
    }

    func stringList(_ input: StringListInput, on eventLoop: EventLoop? = nil, logger: Logger) -> EventLoopFuture<StringListOutput> {
        return client.execute(
            operation: "TestOperation",
            path: "/",
            httpMethod: .POST,
            serviceConfig: config,
            input: input,
            on: eventLoop,
            logger: logger
        )
    }

    func stringListPaginator(_ input: StringListInput, on eventLoop: EventLoop? = nil, onPage: @escaping (StringListOutput, EventLoop)->EventLoopFuture<Bool>) -> EventLoopFuture<Void> {
        return client.paginate(
            input: input,
            command: stringList,
            tokenKey: \StringListOutput.outputToken,
            on: eventLoop,
            onPage: onPage
        )
    }

    // create list of unique strings
    let stringList = Set("Lorem ipsum dolor sit amet, consectetur adipiscing elit, sed do eiusmod tempor incididunt ut labore et dolore magna aliqua. Ut enim ad minim veniam, quis nostrud exercitation ullamco laboris nisi ut aliquip ex ea commodo consequat. Duis aute irure dolor in reprehenderit in voluptate velit esse cillum dolore eu fugiat nulla pariatur. Excepteur sint occaecat cupidatat non proident, sunt in culpa qui officia deserunt mollit anim id est laborum.".split(separator: " ").map {String($0)}).map {$0}

    func stringListServerProcess(_ input: StringListInput) throws -> AWSTestServer.Result<StringListOutput> {
        // send part of array of numbers based on input startIndex and pageSize
        var startIndex = 0
        if let inputToken = input.inputToken {
            guard let stringIndex = stringList.firstIndex(of:inputToken) else { throw Error.didntFindToken }
            startIndex = stringIndex
        }
        let endIndex = min(startIndex+input.pageSize, stringList.count)
        var array: [String] = []
        for i in startIndex..<endIndex {
            array.append(stringList[i])
        }
        var outputToken: String? = nil
        var continueProcessing = false
        if endIndex < stringList.count {
            outputToken = stringList[endIndex]
            continueProcessing = true
        }
        let output = StringListOutput(array: array, outputToken: outputToken)
        return .result(output, continueProcessing: continueProcessing)
    }

    func testStringTokenPaginate() throws {

        // paginate input
        var finalArray: [String] = []
        let input = StringListInput(inputToken: nil, pageSize: 5)
        let future = stringListPaginator(input) { result, eventloop in
            // collate results into array
            finalArray.append(contentsOf: result.array)
            return eventloop.makeSucceededFuture(true)
        }

        // aws server process
        XCTAssertNoThrow(try awsServer.process(stringListServerProcess))

        // wait for response
        XCTAssertNoThrow(try future.wait())

        // verify contents of array
        XCTAssertEqual(finalArray.count, stringList.count)
        for i in 0..<finalArray.count {
            XCTAssertEqual(finalArray[i], stringList[i])
        }
    }

    struct ErrorOutput: AWSShape {
        let error: String
    }

    func testPaginateError() throws {

        // paginate input
        let input = StringListInput(inputToken: nil, pageSize: 5)
        let future = stringListPaginator(input) { _,eventloop in
            return eventloop.makeSucceededFuture(true)
        }

        // aws server process
        XCTAssertNoThrow(try awsServer.process { (request: StringListInput) -> AWSTestServer.Result<StringListOutput> in
            return .error(.badRequest)
        })

        // wait for response
        XCTAssertThrowsError(try future.wait()) { error in
            XCTAssertEqual((error as? AWSResponseError)?.errorCode, "BadRequest")
        }
    }

    func testPaginateErrorAfterFirstRequest() throws {

        // paginate input
        let input = StringListInput(inputToken: nil, pageSize: 5)
        let future = stringListPaginator(input) { _,eventloop in
            return eventloop.makeSucceededFuture(true)
        }

        // aws server process
        var count = 0
        XCTAssertNoThrow(try awsServer.process {(request: StringListInput) -> AWSTestServer.Result<StringListOutput> in
            if count > 0 {
                return .error(.badRequest, continueProcessing: false)
            } else {
                count += 1
                return try stringListServerProcess(request)
            }
        })

        // wait for response
        XCTAssertThrowsError(try future.wait()) { error in
            XCTAssertEqual((error as? AWSResponseError)?.errorCode, "BadRequest")
        }
    }

    func testPaginateEventLoop() throws {
        // paginate input
        let clientEventLoop = client.eventLoopGroup.next()
        let input = StringListInput(inputToken: nil, pageSize: 5)
        let future = stringListPaginator(input, on: clientEventLoop) { _,eventloop in
            XCTAssertTrue(clientEventLoop.inEventLoop)
            XCTAssertTrue(clientEventLoop === eventloop)
            return eventloop.makeSucceededFuture(true)
        }

        // aws server process
        XCTAssertNoThrow(try awsServer.process(stringListServerProcess))
        // wait for response
        XCTAssertNoThrow(try future.wait())
    }
}
