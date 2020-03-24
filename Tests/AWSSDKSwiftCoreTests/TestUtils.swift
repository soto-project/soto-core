//
// Written by Adam Fowler 2020/03/24
//
import Foundation

@propertyWrapper struct EnvironmentVariable<Value: LosslessStringConvertible> {
    var defaultValue: Value
    var variableName: String

    public init(_ variableName: String, default: Value) {
        self.defaultValue = `default`
        self.variableName = variableName
    }
    
    public var wrappedValue: Value {
        get {
            guard let value = ProcessInfo.processInfo.environment[variableName] else { return defaultValue }
            return Value(value) ?? defaultValue
        }
    }
}
