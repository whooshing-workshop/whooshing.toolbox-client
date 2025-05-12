import Vapor
import DataConvertable
import Cryptos
import NIO
import NIOConcurrencyHelpers

/// 一个线程安全的字典类型，封装对原始字典的并发访问控制。
///
/// `SendableDictionary` 使用串行 `DispatchQueue` 实现线程安全，
/// 并显式声明符合 `@unchecked Sendable`，适合用于跨线程共享的数据结构。
///
/// - Note: 请确保 `Key` 和 `Value` 类型本身也是 `Sendable`。
public final class SendableDictionary<Key, Value>: @unchecked Sendable, Sequence where Key: Sendable & Hashable, Value: Sendable {

    public typealias Iterator = Dictionary<Key, Value>.Iterator

    /// 当前字典中所有键的集合（线程安全访问）。
    public var allKey: [Key: Value].Keys {
        lock.withLock { wrapped.keys }
    }

    /// 当前字典中所有值的集合（线程安全访问）。
    public var allValue: [Key: Value].Values {
        lock.withLock { wrapped.values }
    }

    private var wrapped: [Key: Value]
    private let lock = NIOLock()

    /// 创建一个线程安全字典。
    ///
    /// - Parameters:
    ///   - wrapped: 初始化时的字典内容，默认为空字典。
    ///   - lockLabel: 队列标签，可用于调试，默认为随机字符串。
    public init(wrapped: [Key: Value] = [:], lockLabel: String = String(Int.random())) {
        self.wrapped = wrapped
    }

    /// 获取或设置指定键的值，支持线程安全的读写。
    ///
    /// - Parameter key: 要访问的键。
    /// - Returns: 与该键对应的值，若不存在则为 `nil`。
    public subscript(key: Key) -> Value? {
        get { lock.withLock { wrapped[key] } }
        set {
            if let v = newValue {
                lock.withLock { wrapped[key] = v }
            } else {
                lock.withLock { _ = wrapped.removeValue(forKey: key) }
            }
        }
    }

    /// 遍历所有键值对，提供线程安全的 `forEach` 实现。
    ///
    /// - Parameter closure: 对每个键值对执行的闭包。
    public func forEach(closure: @escaping ((key: Key, value: Value)) -> ()) {
        lock.withLock {
            wrapped.forEach { closure($0) }
        }
    }

    /// 支持 for in 遍历字典键值对
    /// 
    /// for (key, value) in sendableDic {
    ///     .........
    /// }
    public func makeIterator() -> Iterator {
        lock.withLock {
            wrapped.makeIterator()
        }
    }

    /// 清空所有的键值对，线程安全
    public func removeAll() {
        lock.withLock {
            wrapped.removeAll()
        }
    }
}
