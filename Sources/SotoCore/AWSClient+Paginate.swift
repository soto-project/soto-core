//===----------------------------------------------------------------------===//
//
// This source file is part of the Soto for AWS open source project
//
// Copyright (c) 2017-2023 the Soto project authors
// Licensed under Apache License v2.0
//
// See LICENSE.txt for license information
// See CONTRIBUTORS.txt for the list of Soto project authors
//
// SPDX-License-Identifier: Apache-2.0
//
//===----------------------------------------------------------------------===//

import Logging
import NIOCore

/// Protocol for all AWSShapes that can be paginated.
/// Adds an initialiser that does a copy but inserts a new integer based pagination token
public protocol AWSPaginateToken: AWSShape {
    associatedtype Token
    func usingPaginationToken(_ token: Token) -> Self
}

extension AWSClient {
    /// Used to access paginated results.
    public struct PaginatorSequence<Input: AWSPaginateToken, Output: AWSShape>: AsyncSequence where Input.Token: Equatable {
        public typealias Element = Output
        let input: Input
        let command: (Input, Logger) async throws -> Output
        let inputKey: KeyPath<Input, Input.Token?>?
        let outputKey: KeyPath<Output, Input.Token?>
        let moreResultsKey: KeyPath<Output, Bool?>?
        let logger: Logger

        /// Initialize PaginatorSequence
        /// - Parameters:
        ///   - input: Initial Input value
        ///   - command: Command to be paginated
        ///   - inputKey: Optional KeyPath for Input token to compare against new key from Output
        ///   - outputKey: KeyPath for Output token used to read new Output
        ///   - moreResultsKey: Optional KeyPath for value indicating whether there are more results
        ///   - logger: Logger
        public init(
            input: Input,
            command: @escaping ((Input, Logger) async throws -> Output),
            inputKey: KeyPath<Input, Input.Token?>? = nil,
            outputKey: KeyPath<Output, Input.Token?>,
            moreResultsKey: KeyPath<Output, Bool?>? = nil,
            logger: Logger = AWSClient.loggingDisabled
        ) {
            self.input = input
            self.command = command
            self.outputKey = outputKey
            self.inputKey = inputKey
            self.moreResultsKey = moreResultsKey
            self.logger = AWSClient.loggingDisabled
        }

        /// Iterator for iterating over `PaginatorSequence`
        public struct AsyncIterator: AsyncIteratorProtocol {
            var input: Input?
            let sequence: PaginatorSequence

            init(sequence: PaginatorSequence) {
                self.sequence = sequence
                self.input = sequence.input
            }

            public mutating func next() async throws -> Output? {
                if let input {
                    let output = try await self.sequence.command(input, self.sequence.logger)
                    if let token = output[keyPath: sequence.outputKey],
                        sequence.inputKey == nil || token != input[keyPath: sequence.inputKey!],
                        sequence.moreResultsKey == nil || output[keyPath: sequence.moreResultsKey!] == true
                    {
                        self.input = input.usingPaginationToken(token)
                    } else {
                        self.input = nil
                    }
                    return output
                }
                return nil
            }
        }

        /// Make async iterator
        public func makeAsyncIterator() -> AsyncIterator {
            AsyncIterator(sequence: self)
        }
    }
}
