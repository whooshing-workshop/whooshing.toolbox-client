public final class Weak<Value>: @unchecked Sendable where Value: AnyObject {
    public weak var value: Value? { __value }
    
    private weak var __value: Value?
    
    public init(_ wrapped: Value) {
        self.__value = wrapped
    }
}

public final class Unowned<Value>: @unchecked Sendable where Value: AnyObject {
    public unowned let value: Value
    
    public init(_ wrapped: Value) {
        self.value = wrapped
    }
}
