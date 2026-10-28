//===----------------------------------------------------------------------===//
//
// This source file is part of the Soto for AWS open source project
//
// Copyright (c) 2017-2022 the Soto project authors
// Licensed under Apache License v2.0
//
// See LICENSE.txt for license information
// See CONTRIBUTORS.txt for the list of Soto project authors
//
// SPDX-License-Identifier: Apache-2.0
//
//===----------------------------------------------------------------------===//

import AsyncHTTPClient
import Atomics
import HTTPTypes
import Logging
import NIOCore
import NIOPosix
import SotoTestUtils
import Synchronization
import Testing

@testable import SotoCore

struct PaginateTests {
    struct PaginateService: AWSService {
        let client: AWSClient
        let config: AWSServiceConfig

        init(client: AWSClient, serviceConfig: AWSServiceConfig) {
            self.client = client
            self.config = serviceConfig
        }

        init(from: PaginateService, patch: AWSServiceConfig.Patch) {
            self.init(client: from.client, serviceConfig: from.config.with(patch: patch))
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
                .init(inputToken: token, pageSize: self.pageSize)
            }
        }

        // conform to Encodable so server can encode these
        struct CounterOutput: AWSDecodableShape, Encodable {
            let array: [Int]
            let outputToken: Int?
        }

        func counter(_ input: CounterInput, logger: Logger) async throws -> CounterOutput {
            try await self.client.execute(
                operation: "TestOperation",
                path: "/",
                httpMethod: .post,
                serviceConfig: self.config,
                input: input,
                logger: logger
            )
        }

        func counterPaginator(_ input: CounterInput) -> AWSClient.PaginatorSequence<CounterInput, CounterOutput> {
            .init(
                input: input,
                command: self.counter,
                inputKey: \CounterInput.inputToken,
                outputKey: \CounterOutput.outputToken,
                logger: TestEnvironment.logger
            )
        }

        func stringList(_ input: StringListInput, logger: Logger) async throws -> StringListOutput {
            try await self.client.execute(
                operation: "TestOperation",
                path: "/",
                httpMethod: .post,
                serviceConfig: self.config,
                input: input,
                logger: logger
            )
        }

        func stringListPaginator(_ input: StringListInput) -> AWSClient.PaginatorSequence<StringListInput, StringListOutput> {
            .init(
                input: input,
                command: self.stringList,
                inputKey: \StringListInput.inputToken,
                outputKey: \StringListOutput.outputToken,
                logger: TestEnvironment.logger
            )
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
                .init(inputToken: token, pageSize: self.pageSize)
            }
        }

        // conform to Encodable so server can encode these
        struct StringListOutput: AWSDecodableShape, Encodable {
            let array: [String]
            let outputToken: String?
        }
    }

    // create list of unique strings
    let stringList = Set(
        "Lorem ipsum dolor sit amet, consectetur adipiscing elit, sed do eiusmod tempor incididunt ut labore et dolore magna aliqua. Ut enim ad minim veniam, quis nostrud exercitation ullamco laboris nisi ut aliquip ex ea commodo consequat. Duis aute irure dolor in reprehenderit in voluptate velit esse cillum dolore eu fugiat nulla pariatur. Excepteur sint occaecat cupidatat non proident, sunt in culpa qui officia deserunt mollit anim id est laborum."
            .split(separator: " ").map { String($0) }
    ).map { $0 }

    func stringListServerProcess(_ input: PaginateService.StringListInput) throws -> PaginateService.StringListOutput {
        // send part of array of numbers based on input startIndex and pageSize
        var startIndex = 0
        if let inputToken = input.inputToken {
            guard let stringIndex = stringList.firstIndex(of: inputToken) else {
                throw MockAWSHTTPClient.HTTPError(status: .notFound, code: "NotFound")
            }
            startIndex = stringIndex
        }
        let endIndex = min(startIndex + input.pageSize, self.stringList.count)
        var array: [String] = []
        for i in startIndex..<endIndex {
            array.append(self.stringList[i])
        }
        var outputToken: String?
        if endIndex < self.stringList.count {
            outputToken = self.stringList[endIndex]
        } else {
            outputToken = input.inputToken
        }
        return PaginateService.StringListOutput(array: array, outputToken: outputToken)
    }

    @Test func testIntegerTokenPaginate() async throws {
        // paginate input
        let input = PaginateService.CounterInput(inputToken: nil, pageSize: 4)
        let arraySize = 23

        let mockHTTPClient = MockAWSHTTPClient { (input: PaginateService.CounterInput) in
            // send part of array of numbers based on input startIndex and pageSize
            let startIndex = input.inputToken ?? 0
            let endIndex = min(startIndex + input.pageSize, arraySize)
            var array: [Int] = []
            for i in startIndex..<endIndex {
                array.append(i)
            }
            return PaginateService.CounterOutput(array: array, outputToken: endIndex != arraySize ? endIndex : nil)
        }
        let client = AWSClient(
            credentialProvider: .empty,
            httpClient: mockHTTPClient
        )
        defer { #expect(throws: Never.self) { try client.syncShutdown() } }

        let service = PaginateService(client: client, serviceConfig: createServiceConfig())
        let finalArray = try await service.counterPaginator(input).reduce([]) {
            $0 + $1.array
        }

        // verify contents of array
        #expect(finalArray.count == arraySize)
        for i in 0..<finalArray.count {
            #expect(finalArray[i] == i)
        }
    }

    @Test func testStringTokenPaginate() async throws {
        // paginate input
        let input = PaginateService.StringListInput(inputToken: nil, pageSize: 5)
        let mockHTTPClient = MockAWSHTTPClient(shapeHandler: self.stringListServerProcess)
        let client = AWSClient(
            credentialProvider: .empty,
            httpClient: mockHTTPClient
        )
        defer { #expect(throws: Never.self) { try client.syncShutdown() } }

        let service = PaginateService(client: client, serviceConfig: createServiceConfig())

        let paginator = service.stringListPaginator(input)
        let finalArray = try await paginator.reduce([]) { $0 + $1.array }
        // verify contents of array
        #expect(finalArray.count == self.stringList.count)
        for i in 0..<finalArray.count {
            #expect(finalArray[i] == self.stringList[i])
        }
    }

    @Test func testPaginateError() async throws {
        // paginate input
        let input = PaginateService.StringListInput(inputToken: nil, pageSize: 5)
        let mockHTTPClient = MockAWSHTTPClient { (input: PaginateService.StringListInput) -> PaginateService.StringListOutput in
            throw MockAWSHTTPClient.HTTPError(status: .badRequest, code: "BadRequest")
        }
        let client = AWSClient(
            credentialProvider: .empty,
            httpClient: mockHTTPClient
        )
        defer { #expect(throws: Never.self) { try client.syncShutdown() } }

        let service = PaginateService(client: client, serviceConfig: createServiceConfig())

        let paginator = service.stringListPaginator(input)
        do {
            _ = try await paginator.reduce([]) { $0 + $1.array }
        } catch {
            #expect((error as? AWSResponseError)?.errorCode == "BadRequest")
        }
    }

    @Test func testPaginateErrorAfterFirstRequest() async throws {
        let count = Atomic(0)
        // paginate input
        let input = PaginateService.StringListInput(inputToken: nil, pageSize: 5)
        let mockHTTPClient = MockAWSHTTPClient { (input: PaginateService.StringListInput) -> PaginateService.StringListOutput in
            if count.add(1, ordering: .relaxed).oldValue > 0 {
                throw MockAWSHTTPClient.HTTPError(status: .badRequest, code: "BadRequest")
            } else {
                return try self.stringListServerProcess(input)
            }
        }
        let client = AWSClient(
            credentialProvider: .empty,
            httpClient: mockHTTPClient
        )
        defer { #expect(throws: Never.self) { try client.syncShutdown() } }

        let service = PaginateService(client: client, serviceConfig: createServiceConfig())

        let paginator = service.stringListPaginator(input)
        do {
            _ = try await paginator.reduce([]) { $0 + $1.array }
        } catch {
            #expect((error as? AWSResponseError)?.errorCode == "BadRequest")
        }
    }
}
