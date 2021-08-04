import Baggage
import Tracing

public enum SotoServiceBaggageKey: Baggage.Key {
    public typealias Value = SotoServiceBaggage
}

public struct SotoServiceBaggage {
    public let serviceName: String
    public let databaseSystem: String?
    public let serviceAttributes: SpanAttributes

    public init(serviceName: String, serviceAttributes: SpanAttributes, databaseSystem: String?) {
        self.serviceName = serviceName
        self.serviceAttributes = serviceAttributes
        self.databaseSystem = databaseSystem
    }
}

