import Testing
@testable import WhooshingClient

#if WHOOSHING_VAPOR
import Vapor
#endif

@Suite("SendableStorage Tests")
struct SendableStorageTests {

    struct FooKey: StorageKey {
        static let defaultValue = "default"
        typealias Value = String
    }

    struct BarKey: StorageKey {
        typealias Value = Int
    }

    @Test("可写入并读取存储值")
    func testStoreAndRetrieve() {
        let storage = SendableStorage()
        storage[FooKey.self] = "hello"
        #expect(storage[FooKey.self] == "hello")
    }

    @Test("值类型隔离")
    func testKeyTypeIsolation() {
        let storage = SendableStorage()
        storage[FooKey.self] = "world"
        storage[BarKey.self] = 42
        #expect(storage[FooKey.self] == "world")
        #expect(storage[BarKey.self] == 42)
    }

    @Test("读取不存在的键应返回 nil")
    func testNilWhenNotSet() {
        let storage = SendableStorage()
        #expect(storage[FooKey.self] == nil)
    }

    @Test("可更新已有值")
    func testValueOverwrite() {
        let storage = SendableStorage()
        storage[BarKey.self] = 1
        storage[BarKey.self] = 99
        #expect(storage[BarKey.self] == 99)
    }

    @Test("设置 nil 会删除该键")
    func testNilRemovesKey() {
        let storage = SendableStorage()
        storage[FooKey.self] = "temp"
        storage[FooKey.self] = nil
        #expect(storage[FooKey.self] == nil)
    }
}
