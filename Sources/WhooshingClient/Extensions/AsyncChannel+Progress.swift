import AsyncAlgorithms
import NIOCore

/// 为 `AsyncChannel` 提供附带进度信息的异步序列包装。
///
/// 每次迭代时返回 `(ProgressContext, DataType)`，用于追踪当前处理位置。
/// 适用于元素类型为 `Collection` 的通道。
public struct AsyncProgressChannel<DataType>: AsyncSequence where DataType: Collection & Sendable {
    public typealias Element = (ProgressContext, DataType)
    public typealias AsyncIterator = Iterator
    typealias Base = AsyncChannel<DataType>
    
    var base: Base
    
    public struct Iterator: AsyncIteratorProtocol {
        var base: Base.Iterator
        var progress = ProgressContext(index: -1)
        var next: Base.Iterator.Element?

        public mutating func next() async throws -> Element? {
            if next == nil { next = await base.next() }
            guard let current = next else { return nil }
            next = await base.next()
            progress = progress.next(current.count, done: next == nil)
            return (progress, current)
        }
    }
    
    public func makeAsyncIterator() -> Iterator {
        Iterator(base: base.makeAsyncIterator())
    }
}

/// 为 `AsyncThrowingChannel` 提供附带进度信息的异步序列包装。
///
/// 每次迭代返回 `(ProgressContext, DataType)`，可抛出错误。
/// 适用于元素类型为 `Collection` 的抛出通道。
public struct AsyncProgressThrowingChannel<DataType, Failure>: AsyncSequence where DataType: Collection & Sendable, Failure: Error {
    public typealias Element = (ProgressContext, DataType)
    public typealias AsyncIterator = Iterator
    typealias Base = AsyncThrowingChannel<DataType, Failure>
    
    var base: Base
    
    public struct Iterator: AsyncIteratorProtocol {
        var base: Base.Iterator
        var progress = ProgressContext(index: -1)
        var next: Base.Iterator.Element?

        public mutating func next() async throws -> Element? {
            if next == nil { next = try await base.next() }
            guard let current = next else { return nil }
            next = try await base.next()
            progress = progress.next(current.count, done: next == nil)
            return (progress, current)
        }
    }
    
    public func makeAsyncIterator() -> Iterator {
        Iterator(base: base.makeAsyncIterator())
    }
}

/// 针对 `ByteBuffer` 的 `AsyncChannel` 提供附带进度的包装序列。
///
/// 每次迭代返回 `(ProgressContext, ByteBuffer)`，以 `readableBytes` 计算进度。
public struct AsyncProgressByteBufferChannel: AsyncSequence {
    public typealias Element = (ProgressContext, ByteBuffer)
    public typealias AsyncIterator = Iterator
    typealias Base = AsyncChannel<ByteBuffer>
    
    var base: Base
    
    public struct Iterator: AsyncIteratorProtocol {
        var base: Base.Iterator
        var progress = ProgressContext(index: -1)
        var next: Base.Iterator.Element?

        public mutating func next() async throws -> Element? {
            if next == nil { next = await base.next() }
            guard let current = next else { return nil }
            next = await base.next()
            progress = progress.next(current.readableBytes, done: next == nil)
            return (progress, current)
        }
    }
    
    public func makeAsyncIterator() -> Iterator {
        Iterator(base: base.makeAsyncIterator())
    }
}

/// 针对 `ByteBuffer` 的 `AsyncThrowingChannel` 提供附带进度的包装序列。
///
/// 每次迭代返回 `(ProgressContext, ByteBuffer)`，以 `readableBytes` 计算进度，可能抛出错误。
public struct AsyncProgressThrowingByteBufferChannel<Failure>: AsyncSequence where Failure: Error {
    public typealias Element = (ProgressContext, ByteBuffer)
    public typealias AsyncIterator = Iterator
    typealias Base = AsyncThrowingChannel<ByteBuffer, Failure>
    
    var base: Base
    
    public struct Iterator: AsyncIteratorProtocol {
        var base: Base.Iterator
        var progress = ProgressContext(index: -1)
        var next: Base.Iterator.Element?

        public mutating func next() async throws -> Element? {
            if next == nil { next = try await base.next() }
            guard let current = next else { return nil }
            next = try await base.next()
            progress = progress.next(current.readableBytes, done: next == nil)
            return (progress, current)
        }
    }
    
    public func makeAsyncIterator() -> Iterator {
        Iterator(base: base.makeAsyncIterator())
    }
}

extension AsyncChannel where Element: Collection {
    /// 返回一个带进度信息的异步通道包装器。
    public func withProgress() -> AsyncProgressChannel<Element> {
        .init(base: self)
    }
}

extension AsyncThrowingChannel where Element: Collection {
    /// 返回一个带进度信息的抛出异步通道包装器。
    public func withProgress() -> AsyncProgressThrowingChannel<Element, Failure> {
        .init(base: self)
    }
}

extension AsyncChannel where Element == ByteBuffer {
    /// 返回一个针对 ByteBuffer 的带进度异步通道包装器。
    public func withProgress() -> AsyncProgressByteBufferChannel {
        .init(base: self)
    }
}

extension AsyncThrowingChannel where Element == ByteBuffer {
    /// 返回一个针对 ByteBuffer 的带进度抛出异步通道包装器。
    public func withProgress() -> AsyncProgressThrowingByteBufferChannel<Failure> {
        .init(base: self)
    }
}
