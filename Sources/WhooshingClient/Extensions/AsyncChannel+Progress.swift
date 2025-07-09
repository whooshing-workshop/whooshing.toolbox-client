import AsyncAlgorithms
import NIOCore

/// 为 `AsyncChannel` 提供附带进度信息的异步序列包装。
///
/// 每次迭代时返回 `(ProgressContext, DataType)`，用于追踪当前处理位置。
/// 适用于元素类型为 `Collection` 的通道。
@frozen
public struct AsyncProgressChannel<DataType>: AsyncSequence where DataType: Collection & Sendable {
    public typealias Element = (ProgressContext, DataType)
    public typealias AsyncIterator = Iterator
    @usableFromInline
    typealias Base = AsyncChannel<DataType>
    
    @usableFromInline
    private(set) var base: Base
    
    @frozen
    public struct Iterator: AsyncIteratorProtocol {
        @usableFromInline
        private(set) var base: Base.Iterator
        @usableFromInline
        private(set) var progress = ProgressContext(index: -1)
        @usableFromInline
        private(set) var next: Base.Iterator.Element?

        @inlinable
        public mutating func next() async throws -> Element? {
            if next == nil { next = await base.next() }
            guard let current = next else { return nil }
            next = await base.next()
            progress = progress.next(current.count, done: next == nil)
            return (progress, current)
        }
        
        @inlinable
        init(base: Base.Iterator, progress: ProgressContext = ProgressContext(index: -1), next: Base.Iterator.Element? = nil) {
            self.base = base
            self.progress = progress
            self.next = next
        }
    }
    
    @inlinable
    public func makeAsyncIterator() -> Iterator {
        Iterator(base: base.makeAsyncIterator())
    }
    
    @inlinable
    init(base: Base) {
        self.base = base
    }
}

/// 为 `AsyncThrowingChannel` 提供附带进度信息的异步序列包装。
///
/// 每次迭代返回 `(ProgressContext, DataType)`，可抛出错误。
/// 适用于元素类型为 `Collection` 的抛出通道。
@frozen
public struct AsyncProgressThrowingChannel<DataType, Failure>: AsyncSequence where DataType: Collection & Sendable, Failure: Error {
    public typealias Element = (ProgressContext, DataType)
    public typealias AsyncIterator = Iterator
    @usableFromInline
    typealias Base = AsyncThrowingChannel<DataType, Failure>
    
    @usableFromInline
    private(set) var base: Base
    
    @frozen
    public struct Iterator: AsyncIteratorProtocol {
        @usableFromInline
        private(set) var base: Base.Iterator
        @usableFromInline
        private(set) var progress = ProgressContext(index: -1)
        @usableFromInline
        private(set) var next: Base.Iterator.Element?

        @inlinable
        public mutating func next() async throws -> Element? {
            if next == nil { next = try await base.next() }
            guard let current = next else { return nil }
            next = try await base.next()
            progress = progress.next(current.count, done: next == nil)
            return (progress, current)
        }
        
        @inlinable
        init(base: Base.Iterator, progress: ProgressContext = ProgressContext(index: -1), next: Base.Iterator.Element? = nil) {
            self.base = base
            self.progress = progress
            self.next = next
        }
    }
    
    @inlinable
    public func makeAsyncIterator() -> Iterator {
        Iterator(base: base.makeAsyncIterator())
    }
    
    @usableFromInline
    init(base: Base) {
        self.base = base
    }
}

/// 针对 `ByteBuffer` 的 `AsyncChannel` 提供附带进度的包装序列。
///
/// 每次迭代返回 `(ProgressContext, ByteBuffer)`，以 `readableBytes` 计算进度。
@frozen
public struct AsyncProgressByteBufferChannel: AsyncSequence {
    public typealias Element = (ProgressContext, ByteBuffer)
    public typealias AsyncIterator = Iterator
    @usableFromInline
    typealias Base = AsyncChannel<ByteBuffer>
    
    @usableFromInline
    private(set) var base: Base
    
    @frozen
    public struct Iterator: AsyncIteratorProtocol {
        @usableFromInline
        private(set) var base: Base.Iterator
        @usableFromInline
        private(set) var progress = ProgressContext(index: -1)
        @usableFromInline
        private(set) var next: Base.Iterator.Element?

        @inlinable
        public mutating func next() async throws -> Element? {
            if next == nil { next = await base.next() }
            guard let current = next else { return nil }
            next = await base.next()
            progress = progress.next(current.readableBytes, done: next == nil)
            return (progress, current)
        }
        
        @inlinable
        init(base: Base.Iterator, progress: ProgressContext = ProgressContext(index: -1), next: Base.Iterator.Element? = nil) {
            self.base = base
            self.progress = progress
            self.next = next
        }
    }
    
    @inlinable
    public func makeAsyncIterator() -> Iterator {
        Iterator(base: base.makeAsyncIterator())
    }
    
    @usableFromInline
    init(base: Base) {
        self.base = base
    }
}

/// 针对 `ByteBuffer` 的 `AsyncThrowingChannel` 提供附带进度的包装序列。
///
/// 每次迭代返回 `(ProgressContext, ByteBuffer)`，以 `readableBytes` 计算进度，可能抛出错误。
@frozen
public struct AsyncProgressThrowingByteBufferChannel<Failure>: AsyncSequence where Failure: Error {
    public typealias Element = (ProgressContext, ByteBuffer)
    public typealias AsyncIterator = Iterator
    @usableFromInline
    typealias Base = AsyncThrowingChannel<ByteBuffer, Failure>
    
    @usableFromInline
    private(set) var base: Base
    
    @frozen
    public struct Iterator: AsyncIteratorProtocol {
        @usableFromInline
        private(set) var base: Base.Iterator
        @usableFromInline
        private(set) var progress = ProgressContext(index: -1)
        @usableFromInline
        private(set) var next: Base.Iterator.Element?

        @inlinable
        public mutating func next() async throws -> Element? {
            if next == nil { next = try await base.next() }
            guard let current = next else { return nil }
            next = try await base.next()
            progress = progress.next(current.readableBytes, done: next == nil)
            return (progress, current)
        }
        
        @inlinable
        init(base: Base.Iterator, progress: ProgressContext = ProgressContext(index: -1), next: Base.Iterator.Element? = nil) {
            self.base = base
            self.progress = progress
            self.next = next
        }
    }
    
    @inlinable
    public func makeAsyncIterator() -> Iterator {
        Iterator(base: base.makeAsyncIterator())
    }
    
    @usableFromInline
    init(base: Base) {
        self.base = base
    }
}

extension AsyncChannel where Element: Collection {
    /// 返回一个带进度信息的异步通道包装器。
    @inlinable
    public func withProgress() -> AsyncProgressChannel<Element> {
        .init(base: self)
    }
}

extension AsyncThrowingChannel where Element: Collection {
    /// 返回一个带进度信息的抛出异步通道包装器。
    @inlinable
    public func withProgress() -> AsyncProgressThrowingChannel<Element, Failure> {
        .init(base: self)
    }
}

extension AsyncChannel where Element == ByteBuffer {
    /// 返回一个针对 ByteBuffer 的带进度异步通道包装器。
    @inlinable
    public func withProgress() -> AsyncProgressByteBufferChannel {
        .init(base: self)
    }
}

extension AsyncThrowingChannel where Element == ByteBuffer {
    /// 返回一个针对 ByteBuffer 的带进度抛出异步通道包装器。
    @inlinable
    public func withProgress() -> AsyncProgressThrowingByteBufferChannel<Failure> {
        .init(base: self)
    }
}




/// 为 `AsyncStream` 提供附带进度信息的异步序列包装。
///
/// 每次迭代时返回 `(ProgressContext, DataType)`，用于追踪当前处理位置。
/// 适用于元素类型为 `Collection` 的通道。
@frozen
public struct AsyncProgressStream<DataType>: AsyncSequence where DataType: Collection & Sendable {
    public typealias Element = (ProgressContext, DataType)
    public typealias AsyncIterator = Iterator
    @usableFromInline
    typealias Base = AsyncStream<DataType>
    
    @usableFromInline
    private(set) var base: Base
    
    @frozen
    public struct Iterator: AsyncIteratorProtocol {
        @usableFromInline
        private(set) var base: Base.Iterator
        @usableFromInline
        private(set) var progress = ProgressContext(index: -1)
        @usableFromInline
        private(set) var next: Base.Iterator.Element?

        @inlinable
        public mutating func next() async throws -> Element? {
            if next == nil { next = await base.next() }
            guard let current = next else { return nil }
            next = await base.next()
            progress = progress.next(current.count, done: next == nil)
            return (progress, current)
        }
        
        @inlinable
        init(base: Base.Iterator, progress: ProgressContext = ProgressContext(index: -1), next: Base.Iterator.Element? = nil) {
            self.base = base
            self.progress = progress
            self.next = next
        }
    }
    
    @inlinable
    public func makeAsyncIterator() -> Iterator {
        Iterator(base: base.makeAsyncIterator())
    }
    
    @usableFromInline
    init(base: Base) {
        self.base = base
    }
}

/// 为 `AsyncThrowingStream` 提供附带进度信息的异步序列包装。
///
/// 每次迭代返回 `(ProgressContext, DataType)`，可抛出错误。
/// 适用于元素类型为 `Collection` 的抛出通道。
@frozen
public struct AsyncProgressThrowingStream<DataType, Failure>: AsyncSequence where DataType: Collection & Sendable, Failure: Error {
    public typealias Element = (ProgressContext, DataType)
    public typealias AsyncIterator = Iterator
    @usableFromInline
    typealias Base = AsyncThrowingStream<DataType, Failure>
    
    @usableFromInline
    private(set) var base: Base
    
    @frozen
    public struct Iterator: AsyncIteratorProtocol {
        @usableFromInline
        private(set) var base: Base.Iterator
        @usableFromInline
        private(set) var progress = ProgressContext(index: -1)
        @usableFromInline
        private(set) var next: Base.Iterator.Element?

        public mutating func next() async throws -> Element? {
            if next == nil { next = try await base.next() }
            guard let current = next else { return nil }
            next = try await base.next()
            progress = progress.next(current.count, done: next == nil)
            return (progress, current)
        }
        
        @inlinable
        init(base: Base.Iterator, progress: ProgressContext = ProgressContext(index: -1), next: Base.Iterator.Element? = nil) {
            self.base = base
            self.progress = progress
            self.next = next
        }
    }
    
    @inlinable
    public func makeAsyncIterator() -> Iterator {
        Iterator(base: base.makeAsyncIterator())
    }
    
    @usableFromInline
    init(base: Base) {
        self.base = base
    }
}

/// 针对 `ByteBuffer` 的 `AsyncStream` 提供附带进度的包装序列。
///
/// 每次迭代返回 `(ProgressContext, ByteBuffer)`，以 `readableBytes` 计算进度。
@frozen
public struct AsyncProgressByteBufferStream: AsyncSequence {
    public typealias Element = (ProgressContext, ByteBuffer)
    public typealias AsyncIterator = Iterator
    @usableFromInline
    typealias Base = AsyncStream<ByteBuffer>
    
    @usableFromInline
    private(set) var base: Base
    
    @frozen
    public struct Iterator: AsyncIteratorProtocol {
        @usableFromInline
        private(set) var base: Base.Iterator
        @usableFromInline
        private(set) var progress = ProgressContext(index: -1)
        @usableFromInline
        private(set) var next: Base.Iterator.Element?

        @inlinable
        public mutating func next() async throws -> Element? {
            if next == nil { next = await base.next() }
            guard let current = next else { return nil }
            next = await base.next()
            progress = progress.next(current.readableBytes, done: next == nil)
            return (progress, current)
        }
        
        @inlinable
        init(base: Base.Iterator, progress: ProgressContext = ProgressContext(index: -1), next: Base.Iterator.Element? = nil) {
            self.base = base
            self.progress = progress
            self.next = next
        }
    }
    
    @inlinable
    public func makeAsyncIterator() -> Iterator {
        Iterator(base: base.makeAsyncIterator())
    }
    
    @usableFromInline
    init(base: Base) {
        self.base = base
    }
}

/// 针对 `ByteBuffer` 的 `AsyncThrowingStream` 提供附带进度的包装序列。
///
/// 每次迭代返回 `(ProgressContext, ByteBuffer)`，以 `readableBytes` 计算进度，可能抛出错误。
@frozen
public struct AsyncProgressThrowingByteBufferStream<Failure>: AsyncSequence where Failure: Error {
    public typealias Element = (ProgressContext, ByteBuffer)
    public typealias AsyncIterator = Iterator
    @usableFromInline
    typealias Base = AsyncThrowingStream<ByteBuffer, Failure>
    
    @usableFromInline
    private(set) var base: Base
    
    @frozen
    public struct Iterator: AsyncIteratorProtocol {
        @usableFromInline
        private(set) var base: Base.Iterator
        @usableFromInline
        private(set) var progress = ProgressContext(index: -1)
        @usableFromInline
        private(set) var next: Base.Iterator.Element?

        @inlinable
        public mutating func next() async throws -> Element? {
            if next == nil { next = try await base.next() }
            guard let current = next else { return nil }
            next = try await base.next()
            progress = progress.next(current.readableBytes, done: next == nil)
            return (progress, current)
        }
        
        @inlinable
        init(base: Base.Iterator, progress: ProgressContext = ProgressContext(index: -1), next: Base.Iterator.Element? = nil) {
            self.base = base
            self.progress = progress
            self.next = next
        }
    }
    
    @inlinable
    public func makeAsyncIterator() -> Iterator {
        Iterator(base: base.makeAsyncIterator())
    }
    
    @usableFromInline
    init(base: Base) {
        self.base = base
    }
}

extension AsyncStream where Element: Collection & Sendable {
    /// 返回一个带进度信息的异步通道包装器。
    @inlinable
    public func withProgress() -> AsyncProgressStream<Element> {
        .init(base: self)
    }
}

extension AsyncThrowingStream where Element: Collection & Sendable {
    /// 返回一个带进度信息的抛出异步通道包装器。
    @inlinable
    public func withProgress() -> AsyncProgressThrowingStream<Element, Failure> {
        .init(base: self)
    }
}

extension AsyncStream where Element == ByteBuffer {
    /// 返回一个针对 ByteBuffer 的带进度异步通道包装器。
    @inlinable
    public func withProgress() -> AsyncProgressByteBufferStream {
        .init(base: self)
    }
}

extension AsyncThrowingStream where Element == ByteBuffer {
    /// 返回一个针对 ByteBuffer 的带进度抛出异步通道包装器。
    @inlinable
    public func withProgress() -> AsyncProgressThrowingByteBufferStream<Failure> {
        .init(base: self)
    }
}
