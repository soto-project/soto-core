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

import Baggage
import Instrumentation
import TracingInstrumentation

private extension String {
    static func random64() -> String {
        String(UInt64.random(in: UInt64.min...UInt64.max) | 1 << 63, radix: 16, uppercase: false)
    }
}

public class TestTracer: TracingInstrument {
    public struct Context {
        let traceId: String
        var parentId: String?
        var sampled: Bool = true

        public init(parentId: String? = nil, sampled: Bool = true) {
            self.traceId = .random64()
            self.parentId = parentId
            self.sampled = sampled
        }
    }

    public class TestSpan: Span {
        public let _test_id: String
        public let _test_operationName: String
        public let _test_kind: SpanKind
        public let _test_startTimestamp: Timestamp
        public private(set) var _test_endTimestamp: Timestamp?
        public private(set) var _test_errors = [Error]()

        public let context: BaggageContext

        public var attributes: SpanAttributes {
            get { [:] }
            set {}
        }

        public var isRecording: Bool { true }

        // TODO: may be removed, see https://github.com/slashmo/gsoc-swift-tracing/issues/134
        public func setStatus(_: SpanStatus) {}

        public func addEvent(_: SpanEvent) {}

        public func recordError(_ error: Error) {
            self._test_errors.append(error)
        }

        public func addLink(_: SpanLink) {}

        public func end(at timestamp: Timestamp) {
            self._test_endTimestamp = timestamp
        }

        init(operationName: String, kind: SpanKind, startTimestamp: Timestamp, context: BaggageContext) {
            let spanId = String.random64()
            self._test_id = spanId
            self._test_operationName = operationName
            self._test_kind = kind
            self._test_startTimestamp = startTimestamp
            // update context
            // TODO: handle missing context, expected behaviour not defined and is tracer implementation specific
            var context = context
            context.test?.parentId = spanId
            self.context = context
        }
    }

    public private(set) var _test_recordedSpans = [TestSpan]()

    public init() {}

    public func extract<Carrier, Extractor>(
        _ carrier: Carrier,
        into context: inout BaggageContext,
        using extractor: Extractor
    ) where Carrier == Extractor.Carrier, Extractor: ExtractorProtocol {
        // not needed
    }

    public func inject<Carrier, Injector>(
        _ context: BaggageContext,
        into carrier: inout Carrier,
        using injector: Injector
    ) where Carrier == Injector.Carrier, Injector: InjectorProtocol {
        // not needed
    }

    public func startSpan(
        named operationName: String,
        context: BaggageContextCarrier,
        ofKind kind: SpanKind,
        at timestamp: Timestamp
    ) -> Span {
        let span = TestSpan(
            operationName: operationName,
            kind: kind,
            startTimestamp: timestamp,
            context: context.baggage
        )
        self._test_recordedSpans.append(span)
        return span
    }

    public func forceFlush() {}
}

// MARK: - Baggage

private enum TestKey: BaggageContextKey {
    typealias Value = TestTracer.Context
    var name: String { "Test" }
}

extension BaggageContext {
    public var test: TestTracer.Context? {
        get {
            self[TestKey.self]
        }
        set {
            self[TestKey.self] = newValue
        }
    }
}
