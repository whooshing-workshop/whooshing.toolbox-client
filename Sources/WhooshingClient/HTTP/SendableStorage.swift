public final class SendableStorage: Sendable {
    private let storage: SendableDictionary<ObjectIdentifier, Sendable> = .init()
    
    public subscript<Key: StorageKey>(key: Key.Type) -> Key.Value? {
        get {
            guard let value = storage[ObjectIdentifier(Key.self)] as? Key.Value else {
                return nil
            }
            return value
        }
        set {
            storage[ObjectIdentifier(key.self)] = newValue
        }
    }
}

public protocol StorageKey {
    associatedtype Value: Sendable
}
