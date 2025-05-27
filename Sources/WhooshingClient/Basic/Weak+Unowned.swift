import NIOConcurrencyHelpers

/// 一个弱引用包装器，用于对引用类型进行弱引用，避免循环引用。
/// 通过 `NIOLock` 实现线程安全读写，适用于并发环境下的弱引用访问。
/// 遵循 `@unchecked Sendable`，开发者需确保封装对象本身是线程安全的。
public final class Weak<Value>: @unchecked Sendable where Value: AnyObject {
    /// 当前弱引用对象，若对象已释放则为 nil。
    /// 该属性通过锁机制进行同步，确保线程安全访问。
    public weak var value: Value? {
        get { lock.withLock { __value } }
        set { lock.withLock { __value = newValue } }
    }
    
    /// 实际存储弱引用的私有属性。
    private weak var __value: Value?
    private let lock = NIOLock()
    
    /// 使用一个引用类型对象初始化包装器。
    /// - Parameter wrapped: 要包装的对象。
    public init(_ wrapped: Value) {
        self.__value = wrapped
    }
}

/// 一个无主引用包装器，用于对引用类型进行无主引用访问。
/// 无主引用在被访问时要求对象仍然存在，否则会崩溃。
/// 使用 `NIOLock` 实现线程安全读写，适用于生命周期受控明确的并发场景。
/// 同样遵循 `@unchecked Sendable`，开发者需确保引用对象本身为线程安全。
public final class Unowned<Value>: @unchecked Sendable where Value: AnyObject {
    /// 当前无主引用的对象。
    /// 该属性通过锁机制进行同步，确保线程安全访问。
    public unowned var value: Value {
        get { lock.withLock { __value } }
        set { lock.withLock { __value = newValue } }
    }
    
    private unowned var __value: Value
    private let lock = NIOLock()
    
    /// 使用一个引用类型对象初始化包装器。
    /// - Parameter wrapped: 要包装的对象。
    public init(_ wrapped: Value) {
        self.__value = wrapped
    }
}
