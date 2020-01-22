//
//  PaginateTests.swift
//  AWSSDKSwiftCoreTests
//
//  Created by Adam Fowler on 2020/01/21.
//
//

import NIO
import XCTest
@testable import AWSSDKSwiftCore

class PaginateTests: XCTestCase {

    var eventLoopGroup: EventLoopGroup!
    var awsServer: AWSTestServer!
    var client: AWSClient!

    override func setUp() {
        // create server and client
        eventLoopGroup = MultiThreadedEventLoopGroup(numberOfThreads: System.coreCount)
        awsServer = AWSTestServer(serviceProtocol: .json, eventLoopGroup: eventLoopGroup)
        client = AWSClient(
            region: .useast1,
            service:"TestClient",
            serviceProtocol: ServiceProtocol(type: .json, version: ServiceProtocol.Version(major: 1, minor: 1)),
            apiVersion: "2020-01-21",
            endpoint: "http://localhost:\(awsServer.serverPort)",
            middlewares: [AWSLoggingMiddleware()],
            eventLoopGroupProvider: .shared(eventLoopGroup)
        )
    }
    
    override func tearDown() {
        XCTAssertNoThrow(try self.awsServer.stop())
        XCTAssertNoThrow(try self.eventLoopGroup.syncShutdownGracefully())
        self.eventLoopGroup = nil
    }
    
    // test structures/functions
    struct CounterInput: AWSShape, AWSPaginateIntToken {
        public static var _members: [AWSShapeMember] = [
            AWSShapeMember(label: "inputToken", required: true, type: .integer)
        ]
        let inputToken: Int?
        let pageSize: Int
        
        init(inputToken: Int?, pageSize: Int) {
            self.inputToken = inputToken
            self.pageSize = pageSize
        }
        init(_ original: CounterInput, token: Int) {
            self.inputToken = token
            self.pageSize = original.pageSize
        }
    }
    struct CounterOutput: AWSShape {
        let array: [Int]
        let outputToken: Int?
    }
    
    func counter(_ input: CounterInput) -> EventLoopFuture<CounterOutput> {
        return client.send(operation: "TestOperation", path: "/", httpMethod: "POST", input: input)
    }
    
    func counterPaginator(_ input: CounterInput, onPage: @escaping ([Int], EventLoop)->EventLoopFuture<Bool>) -> EventLoopFuture<Void> {
        return client.paginate(input: input, command: counter, resultKey: \CounterOutput.array, tokenKey: \CounterOutput.outputToken, onPage: onPage)
    }
    
    #if !os(Linux)
    func testPaginate() throws {
        
        // paginate input
        var finalArray: [Int] = []
        let input = CounterInput(inputToken: nil, pageSize: 4)
        let future = counterPaginator(input) { result, eventloop in
            // collate results into array
            finalArray.append(contentsOf: result)
            return eventloop.makeSucceededFuture(true)
        }
        
        let arraySize = 23
        do {
            // aws server process
            try awsServer.process { (input: CounterInput) throws -> AWSTestServer.Result<CounterOutput> in
                // send part of array of numbers based on input startIndex and pageSize
                let startIndex = input.inputToken ?? 0
                let endIndex = min(startIndex+input.pageSize, arraySize)
                var array: [Int] = []
                for i in startIndex..<endIndex {
                    array.append(i)
                }
                let continueProcessing = (endIndex != arraySize)
                let output = CounterOutput(array: array, outputToken: endIndex != arraySize ? endIndex : nil)
                return AWSTestServer.Result(output: output, continueProcessing: continueProcessing)
            }

            // wait for response
            try future.wait()
        } catch {
            print(error)
        }
        
        // verify contents of array
        XCTAssertEqual(finalArray.count, arraySize)
        for i in 0..<finalArray.count {
            XCTAssertEqual(finalArray[i], i)
        }
    }
    #endif

    static var allTests : [(String, (PaginateTests) -> () throws -> Void)] {
        return [
            //("testPaginate", testPaginate),
        ]
    }
}
