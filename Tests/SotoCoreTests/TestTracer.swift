//===----------------------------------------------------------------------===//
//
// This source file is part of the Soto for AWS open source project
//
// Copyright (c) 2023 the Soto project authors
// Licensed under Apache License v2.0
//
// See LICENSE.txt for license information
// See CONTRIBUTORS.txt for the list of Soto project authors
//
// SPDX-License-Identifier: Apache-2.0
//
//===----------------------------------------------------------------------===//

//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift Distributed Tracing open source project
//
// Copyright (c) 2020-2023 Apple Inc. and the Swift Distributed Tracing project
// authors
// Licensed under Apache License v2.0
//
// See LICENSE.txt for license information
//
// SPDX-License-Identifier: Apache-2.0
//
//===----------------------------------------------------------------------===//

import Dispatch
import Instrumentation
import NIOConcurrencyHelpers
import ServiceContextModule
import Tracing

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif

final class TestTracer: Tracer, Sendable {
    let spans = NIOLockedValueBox<[TestSpan]>([])
    let onEndSpan: @Sendable (TestSpan) -> Void

    init(_ onEndSpan: @Sendable @escaping (TestSpan) -> Void) {
        self.onEndSpan = onEndSpan
    }

    func startSpan(
        _ operationName: String,
        context: @autoclosure () -> ServiceContext,
        ofKind kind: SpanKind,
        at instant: @autoclosure () -> some TracerInstant,
        function: String,
        file fileID: String,
        line: UInt
    ) -> TestSpan {
        let span = TestSpan(
            operationName: operationName,
            startTime: instant(),
            context: context(),
            kind: kind,
            onEnd: self.onEndSpan
        )
        self.spans.withLockedValue { $0.append(span) }
        return span
    }

    public func forceFlush() {}

    func extract<Carrier, Extract>(_ carrier: Carrier, into context: inout ServiceContext, using extractor: Extract)
    where
        Extract: Extractor,
        Carrier == Extract.Carrier
    {
        let traceID = extractor.extract(key: "trace-id", from: carrier) ?? UUID().uuidString
        context.traceID = traceID
    }

    func inject<Carrier, Inject>(_ context: ServiceContext, into carrier: inout Carrier, using injector: Inject)
    where
        Inject: Injector,
        Carrier == Inject.Carrier
    {
        guard let traceID = context.traceID else { return }
        injector.inject(traceID, forKey: "trace-id", into: &carrier)
    }
}

extension TestTracer {
    enum TraceIDKey: ServiceContextKey {
        typealias Value = String
    }

    enum SpanIDKey: ServiceContextKey {
        typealias Value = String
    }
}

extension ServiceContext {
    var traceID: String? {
        get {
            self[TestTracer.TraceIDKey.self]
        }
        set {
            self[TestTracer.TraceIDKey.self] = newValue
        }
    }

    var spanID: String? {
        get {
            self[TestTracer.SpanIDKey.self]
        }
        set {
            self[TestTracer.SpanIDKey.self] = newValue
        }
    }
}

final class TestSpan: Span, Sendable {
    struct _Internal {
        var status: SpanStatus?
        var endTimestampNanosSinceEpoch: UInt64?
        var recordedErrors: [(Error, SpanAttributes)] = []
        var operationName: String
        var events = [SpanEvent]() {
            didSet {
                self.isRecording = !self.events.isEmpty
            }
        }

        var links = [SpanLink]()
        var attributes: SpanAttributes = [:] {
            didSet {
                self.isRecording = !self.attributes.isEmpty
            }
        }

        var isRecording = false

        init(operationName: String) {
            self.operationName = operationName
        }
    }

    private let _internal: NIOLockedValueBox<_Internal>

    let context: ServiceContext
    let kind: SpanKind
    let startTimestampNanosSinceEpoch: UInt64

    var status: SpanStatus? { self._internal.withLockedValue { $0.status } }

    var endTimestampNanosSinceEpoch: UInt64? { self._internal.withLockedValue { $0.endTimestampNanosSinceEpoch } }

    var operationName: String {
        get { self._internal.withLockedValue { $0.operationName } }
        set { self._internal.withLockedValue { $0.operationName = newValue } }
    }

    var recordedErrors: [(Error, SpanAttributes)] { self._internal.withLockedValue { $0.recordedErrors } }
    var events: [SpanEvent] { self._internal.withLockedValue { $0.events } }
    var links: [SpanLink] { self._internal.withLockedValue { $0.links } }
    var attributes: SpanAttributes {
        get { self._internal.withLockedValue { $0.attributes } }
        set { self._internal.withLockedValue { $0.attributes = newValue } }
    }

    var isRecording: Bool { self._internal.withLockedValue { $0.isRecording } }

    let onEnd: @Sendable (TestSpan) -> Void

    init(
        operationName: String,
        startTime: some TracerInstant,
        context: ServiceContext,
        kind: SpanKind,
        onEnd: @escaping @Sendable (TestSpan) -> Void
    ) {
        self._internal = .init(.init(operationName: operationName))
        self.startTimestampNanosSinceEpoch = startTime.nanosecondsSinceEpoch
        self.context = context
        self.onEnd = onEnd
        self.kind = kind
    }

    func setStatus(_ status: SpanStatus) {
        self._internal.withLockedValue {
            $0.status = status
            $0.isRecording = true
        }
    }

    func addLink(_ link: SpanLink) {
        self._internal.withLockedValue {
            $0.links.append(link)
        }
    }

    func addEvent(_ event: SpanEvent) {
        self._internal.withLockedValue {
            $0.events.append(event)
        }
    }

    func recordError(_ error: Error, attributes: SpanAttributes, at instant: @autoclosure () -> some TracerInstant) {
        self._internal.withLockedValue {
            $0.recordedErrors.append((error, attributes))
        }
    }

    func end(at instant: @autoclosure () -> some TracerInstant) {
        self._internal.withLockedValue {
            $0.endTimestampNanosSinceEpoch = instant().nanosecondsSinceEpoch
        }
        self.onEnd(self)
    }
}
