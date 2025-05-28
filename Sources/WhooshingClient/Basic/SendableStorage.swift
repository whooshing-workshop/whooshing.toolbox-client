/// 一个线程安全的泛型存储容器，基于 Sendable 类型构建。
/// 支持以类型为键进行数据存取，常用于跨类型安全共享数据。
public final class SendableStorage: Sendable {
    /// 内部存储字典，使用类型标识符作为键，值为 Sendable 协议的实例。
    private let storage: SendableDictionary<ObjectIdentifier, Sendable> = .init()
    
    public protocol Key {
        associatedtype Value: Sendable
    }

    /// 以类型为键的下标访问方式，用于存取符合 `StorageKey` 协议的键对应的值。
    ///
    /// - Parameter key: 遵循 `StorageKey` 协议的类型，用作键。
    /// - Returns: 对应类型的值，如果未设置则为 nil。
    public subscript<T: Key>(key: T.Type) -> T.Value? {
        get {
            guard let value = storage[ObjectIdentifier(T.self)] as? T.Value else {
                return nil
            }
            return value
        }
        set {
            storage[ObjectIdentifier(key.self)] = newValue
        }
    }
}
