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
@testable import AWSSDKSwiftCore
import AWSTestUtils
import NIO
import XCTest

class PaginateTests: XCTestCase {
    enum Error: Swift.Error {
        case didntFindToken
    }

    var awsServer: AWSTestServer!
    var eventLoopGroup: EventLoopGroup!
    var httpClient: HTTPClient!
    var client: AWSClient!
    var config: AWSServiceConfig!

    override func setUp() {
        // create server and client
        self.awsServer = AWSTestServer(serviceProtocol: .json)
        self.eventLoopGroup = MultiThreadedEventLoopGroup(numberOfThreads: 3)
        self.httpClient = AsyncHTTPClient.HTTPClient(eventLoopGroupProvider: .shared(self.eventLoopGroup))
        self.config = createServiceConfig(serviceProtocol: .json(version: "1.1"), endpoint: self.awsServer.address)
        self.client = createAWSClient(credentialProvider: .empty, retryPolicy: .noRetry, httpClientProvider: .shared(self.httpClient))
    }

    override func tearDown() {
        XCTAssertNoThrow(try self.awsServer.stop())
        XCTAssertNoThrow(try self.client.syncShutdown())
        XCTAssertNoThrow(try self.httpClient.syncShutdown())
        XCTAssertNoThrow(try self.eventLoopGroup.syncShutdownGracefully())
    }

    func testIntegerTokenPaginate() throws {
        // paginate input
        let service = PaginateTestService(client: client, config: config)
        var finalArray: [Int] = []
        let input = PaginateTestService.CounterInput(inputToken: nil, pageSize: 4)
        let future = service.counterPaginator(input) { result, eventloop in
            // collate results into array
            finalArray.append(contentsOf: result.array)
            return eventloop.makeSucceededFuture(true)
        }

        let arraySize = 23
        // aws server process
        XCTAssertNoThrow(try self.awsServer.process { (input: PaginateTestService.CounterInput) throws -> AWSTestServer.Result<PaginateTestService.CounterOutput> in
            // send part of array of numbers based on input startIndex and pageSize
            let startIndex = input.inputToken ?? 0
            let endIndex = min(startIndex + input.pageSize, arraySize)
            var array: [Int] = []
            for i in startIndex..<endIndex {
                array.append(i)
            }
            let continueProcessing = (endIndex != arraySize)
            let output = PaginateTestService.CounterOutput(array: array, outputToken: endIndex != arraySize ? endIndex : nil)
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

    // create list of unique strings
    let stringList = Set("Lorem ipsum dolor sit amet, consectetur adipiscing elit, sed do eiusmod tempor incididunt ut labore et dolore magna aliqua. Ut enim ad minim veniam, quis nostrud exercitation ullamco laboris nisi ut aliquip ex ea commodo consequat. Duis aute irure dolor in reprehenderit in voluptate velit esse cillum dolore eu fugiat nulla pariatur. Excepteur sint occaecat cupidatat non proident, sunt in culpa qui officia deserunt mollit anim id est laborum.".split(separator: " ").map { String($0) }).map { $0 }

    func stringListServerProcess(_ input: PaginateTestService.StringListInput) throws -> AWSTestServer.Result<PaginateTestService.StringListOutput> {
        // send part of array of numbers based on input startIndex and pageSize
        var startIndex = 0
        if let inputToken = input.inputToken {
            guard let stringIndex = stringList.firstIndex(of: inputToken) else { throw Error.didntFindToken }
            startIndex = stringIndex
        }
        let endIndex = min(startIndex + input.pageSize, self.stringList.count)
        var array: [String] = []
        for i in startIndex..<endIndex {
            array.append(self.stringList[i])
        }
        var outputToken: String?
        var continueProcessing = false
        if endIndex < self.stringList.count {
            outputToken = self.stringList[endIndex]
            continueProcessing = true
        }
        let output = PaginateTestService.StringListOutput(array: array, outputToken: outputToken)
        return .result(output, continueProcessing: continueProcessing)
    }

    func testStringTokenPaginate() throws {
        // paginate input
        var finalArray: [String] = []
        let service = PaginateTestService(client: client, config: config)
        let input = PaginateTestService.StringListInput(inputToken: nil, pageSize: 5)
        let future = service.stringListPaginator(input) { result, eventloop in
            // collate results into array
            finalArray.append(contentsOf: result.array)
            return eventloop.makeSucceededFuture(true)
        }

        // aws server process
        XCTAssertNoThrow(try self.awsServer.process(self.stringListServerProcess))

        // wait for response
        XCTAssertNoThrow(try future.wait())

        // verify contents of array
        XCTAssertEqual(finalArray.count, self.stringList.count)
        for i in 0..<finalArray.count {
            XCTAssertEqual(finalArray[i], self.stringList[i])
        }
    }

    struct ErrorOutput: AWSShape {
        let error: String
    }

    func testPaginateError() throws {
        // paginate input
        let service = PaginateTestService(client: client, config: config)
        let input = PaginateTestService.StringListInput(inputToken: nil, pageSize: 5)
        let future = service.stringListPaginator(input) { _, eventloop in
            return eventloop.makeSucceededFuture(true)
        }

        // aws server process
        XCTAssertNoThrow(try self.awsServer.process { (_: PaginateTestService.StringListInput) -> AWSTestServer.Result<PaginateTestService.StringListOutput> in
            return .error(.badRequest)
        })

        // wait for response
        XCTAssertThrowsError(try future.wait()) { error in
            XCTAssertEqual((error as? AWSResponseError)?.errorCode, "BadRequest")
        }
    }

    func testPaginateErrorAfterFirstRequest() throws {
        // paginate input
        let service = PaginateTestService(client: client, config: config)
        let input = PaginateTestService.StringListInput(inputToken: nil, pageSize: 5)
        let future = service.stringListPaginator(input) { _, eventloop in
            return eventloop.makeSucceededFuture(true)
        }

        // aws server process
        var count = 0
        XCTAssertNoThrow(try self.awsServer.process { (request: PaginateTestService.StringListInput) -> AWSTestServer.Result<PaginateTestService.StringListOutput> in
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
        let clientEventLoop = self.client.eventLoopGroup.next()
        let service = PaginateTestService(client: client, config: config)
        let input = PaginateTestService.StringListInput(inputToken: nil, pageSize: 5)
        let future = service.delegating(to: clientEventLoop).stringListPaginator(input) { _, eventloop in
            XCTAssertTrue(clientEventLoop.inEventLoop)
            XCTAssertTrue(clientEventLoop === eventloop)
            return eventloop.makeSucceededFuture(true)
        }

        // aws server process
        XCTAssertNoThrow(try self.awsServer.process(self.stringListServerProcess))
        // wait for response
        XCTAssertNoThrow(try future.wait())
    }
}

/// Test service used for pagination
struct PaginateTestService: AWSService {
    func withNewContext(_ process: (AWSServiceContext) -> AWSServiceContext) -> PaginateTestService {
        return PaginateTestService(client: self.client, config: self.config, context: process(self.context))
    }

    public let client: AWSClient
    public let config: AWSServiceConfig
    public let context: AWSServiceContext

    init(client: AWSClient, config: AWSServiceConfig, context: AWSServiceContext = TestEnvironment.context) {
        self.client = client
        self.config = config
        self.context = context
    }

    func counter(_ input: CounterInput) -> EventLoopFuture<CounterOutput> {
        return self.client.execute(
            operation: "TestOperation",
            path: "/",
            httpMethod: .POST,
            input: input,
            config: self.config,
            context: self.context
        )
    }

    func counterPaginator(_ input: CounterInput, onPage: @escaping (CounterOutput, EventLoop) -> EventLoopFuture<Bool>) -> EventLoopFuture<Void> {
        return self.client.paginate(
            input: input,
            command: self.counter,
            tokenKey: \CounterOutput.outputToken,
            context: TestEnvironment.context,
            onPage: onPage
        )
    }

    func stringList(_ input: StringListInput) -> EventLoopFuture<StringListOutput> {
        return self.client.execute(
            operation: "TestOperation",
            path: "/",
            httpMethod: .POST,
            input: input,
            config: self.config,
            context: self.context
        )
    }

    func stringListPaginator(_ input: StringListInput, onPage: @escaping (StringListOutput, EventLoop) -> EventLoopFuture<Bool>) -> EventLoopFuture<Void> {
        return self.client.paginate(
            input: input,
            command: self.stringList,
            tokenKey: \StringListOutput.outputToken,
            context: self.context,
            onPage: onPage
        )
    }
}

extension PaginateTestService {
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
}
