//===----------------------------------------------------------------------===//
//
// This source file is part of the Soto for AWS open source project
//
// Copyright (c) 2017-2020 the Soto project authors
// Licensed under Apache License v2.0
//
// See LICENSE.txt for license information
// See CONTRIBUTORS.txt for the list of Soto project authors
//
// SPDX-License-Identifier: Apache-2.0
//
//===----------------------------------------------------------------------===//

import NIO

extension AWSClient {
    enum WaiterState {
        case success
        case retry
        case failure
    }

    struct Waiter<Input, Output> {
        struct Acceptor {
            let state: WaiterState
            let matcher: AWSMatcher
        }
        let acceptors: [Acceptor]
        let maxRetryAttempts: Int
        let command: (Input, Logger, EventLoop?) -> EventLoopFuture<Output>
    }

    func wait<Input, Output>(
        _ input: Input,
        waiter: Waiter<Input, Output>,
        maxWaitTime: TimeAmount,
        logger: Logger = AWSClient.loggingDisabled,
        on eventLoop: EventLoop? = nil
    ) -> EventLoopFuture<Void> {
        let eventLoop = eventLoop ?? eventLoopGroup.next()
        let promise = eventLoop.makePromise(of: Void.self)

        func attempt() {
            waiter.command(input, logger, eventLoop)
                .whenComplete { result in
                    var state: WaiterState? = nil
                    for acceptor in waiter.acceptors {
                        if acceptor.matcher.match(result: result.map { $0 }) {
                            state = acceptor.state
                            break
                        }
                    }
                    print(state)
                    switch state {
                    case .success:
                        promise.succeed(())
                    case .failure:
                        if case .failure(let error) = result {
                            promise.fail(error)
                        } else {
                            promise.fail(ClientError.waiterFailed)
                        }
                    case .retry:
                        eventLoop.scheduleTask(in: .seconds(1)) { attempt() }
                    case .none:
                        if case .failure(let error) = result {
                            promise.fail(error)
                        } else {
                            eventLoop.scheduleTask(in: .seconds(1)) { attempt() }
                        }
                    }
                }
        }
        attempt()
        return promise.futureResult
    }
}
