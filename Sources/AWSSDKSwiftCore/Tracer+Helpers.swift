//
//  File.swift
//
//
//  Created by Michał A on 2020/9/8.
//

import Baggage
import Instrumentation
import TracingInstrumentation

// extensions based on XRaySDK API, may be redundant see https://github.com/slashmo/gsoc-swift-tracing/issues/125

internal extension TracingInstrument {
    func span<T>(
        named name: String,
        context: BaggageContextCarrier,
        ofKind kind: TracingInstrumentation.SpanKind = .internal,
        at timestamp: TracingInstrumentation.Timestamp = .now(),
        body: (TracingInstrumentation.Span) throws -> T
    )
        rethrows -> T
    {
            var span = InstrumentationSystem.tracingInstrument.startSpan(
                named: name,
                context: context,
                ofKind: kind,
                at: timestamp
            )
            defer {
                span.end()
            }
            do {
                return try body(span)
            } catch {
                span.recordError(error)
                throw error
            }
        }

    func span<T, E>(
        named name: String,
        context: BaggageContextCarrier,
        ofKind kind: TracingInstrumentation.SpanKind = .internal,
        at timestamp: TracingInstrumentation.Timestamp = .now(),
        body: (TracingInstrumentation.Span) throws -> Result<T, E>
    )
        rethrows -> Result<T, E>
    {
            var span = InstrumentationSystem.tracingInstrument.startSpan(
                named: name,
                context: context,
                ofKind: kind,
                at: timestamp
            )
            defer {
                span.end()
            }
            do {
                let result = try body(span)
                if case Result<T, E>.failure(let error) = result {
                    span.recordError(error)
                }
                return result
            } catch {
                span.recordError(error)
                throw error
            }
        }

    func span<T>(
        named name: String,
        context: BaggageContextCarrier,
        ofKind kind: TracingInstrumentation.SpanKind = .internal,
        at timestamp: TracingInstrumentation.Timestamp = .now(),
        body: (TracingInstrumentation.Span) -> EventLoopFuture<T>
    ) -> EventLoopFuture<T> {
        var span = InstrumentationSystem.tracingInstrument.startSpan(
            named: name,
            context: context,
            ofKind: kind,
            at: timestamp
        )
        return body(span).always { result in
            if case Result<T, Error>.failure(let error) = result {
                span.recordError(error)
            }
            span.end()
        }
    }
}

internal extension EventLoopFuture {
    func endSpan(_ span: TracingInstrumentation.Span) -> EventLoopFuture<Value> {
        var span = span // TODO: see https://github.com/slashmo/gsoc-swift-tracing/issues/119
        whenComplete { result in
            if case Result<Value, Error>.failure(let error) = result {
                span.recordError(error)
            }
            span.end()
        }
        return self
    }
}
