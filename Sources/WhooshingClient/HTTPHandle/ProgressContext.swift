import Foundation
import AsyncAlgorithms
import NIOCore

#if WHOOSHING_VAPOR
import Vapor
#endif


/// 表示某个数据传输或处理任务的进度上下文。
///
/// `ProgressContext` 用于追踪任务的当前进度，包括已传输字节数、总字节数、耗时、速度等信息，
/// 同时携带与该任务相关的通道信息和用户自定义的响应值。
public struct ProgressContext: Sendable, CustomStringConvertible {
    
    /// 当前任务在整个进度列表中的索引编号（适用于分片或批量任务）。
    public let index: Int

    /// 是否已完成任务。
    public let done: Bool

    /// 正处理的数据块的大小
    public let bytes: Int
    
    /// 当前已传输或处理的字节数。
    public let curBytes: Int

    /// 预计总的字节数，如果未知则为 `nil`。
    public let totalBytes: Int?

    /// 任务开始的时间。
    public let startDate: Date
    
    public init(index: Int = 0, done: Bool = false, bytes: Int = 0, curBytes: Int = 0, totalBytes: Int? = nil, startDate: Date = Date()) {
        self.index = index
        self.done = done
        self.curBytes = curBytes
        self.totalBytes = totalBytes
        self.startDate = startDate
        self.bytes = bytes
    }

    /// 当前字节传输进度（0~1），如果 `totalBytes` 未知或为 0，则为 `nil`。
    public var bytesPersentage: Double? {
        if let tb = totalBytes, tb > 0 {
            return Double(curBytes) / Double(tb)
        }
        return nil
    }

    /// 格式化的字节传输百分比字符串（例如 "68.2%"），如果无法计算则返回 `"~%"`。
    public var bytesPersentageStr: String {
        (bytesPersentage == nil ? "~" : String(Float(Int(bytesPersentage! * 100 * 100) / 100))) + "%"
    }

    /// 格式化的总字节数字符串（例如 "12.3 MB"），如果未知则返回 `"~B"`。
    public var totalBytesStr: String {
        totalBytes == nil ? "~B" : ChunkTool.formatByteSize(totalBytes!)
    }

    /// 格式化的当前字节数字符串（例如 "3.5 MB"）。
    public var curBytesStr: String {
        ChunkTool.formatByteSize(curBytes)
    }

    /// 当前的传输速度（字节每秒），如果耗时为 0 则为 `nil`。
    public var speed: Double? {
        let timeCost = Double(timeCost)
        if timeCost > 0 {
            return (Double(curBytes) / timeCost)
        } else {
            return nil
        }
    }

    /// 格式化的传输速度字符串（例如 "1.2MB/s"），如果无法计算则返回 `"~B/s"`。
    public var speedStr: String {
        if let speed = self.speed {
            return ChunkTool.formatByteSize(.init(speed)) + "/s"
        } else {
            return "~B/s"
        }
    }

    /// 当前任务已耗费的时间字符串（单位：秒）。
    public var timeCost: TimeInterval {
        Date().timeIntervalSince(startDate)
    }
    
    public var timeCostStr: String {
        String(format: "%.6fs", self.timeCost)
    }

    /// 返回当前进度上下文的字符串描述，方便调试和日志记录。
    public var description: String {
        "Progress(\(index), 字节进度: \(bytesPersentageStr) [\(curBytesStr)(\(curBytes))-\(totalBytesStr)(\(totalBytes == nil ? "~" : String(totalBytes!)))], 大小: \(bytes), 完成: \(done), 耗时: \(timeCostStr), 速度: \(speedStr))"
    }
    
    public func next(_ dataSize: Int, done: Bool = false) -> Self {
        .init(index: index + 1, done: done, bytes: dataSize, curBytes: curBytes + dataSize, totalBytes: totalBytes, startDate: startDate)
    }
}

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
    public func withProgress() -> AsyncProgressChannel<Element> {
        .init(base: self)
    }
}

extension AsyncThrowingChannel where Element: Collection {
    public func withProgress() -> AsyncProgressThrowingChannel<Element, Failure> {
        .init(base: self)
    }
}

extension AsyncChannel where Element == ByteBuffer {
    public func withProgress() -> AsyncProgressByteBufferChannel {
        .init(base: self)
    }
}

extension AsyncThrowingChannel where Element == ByteBuffer {
    public func withProgress() -> AsyncProgressThrowingByteBufferChannel<Failure> {
        .init(base: self)
    }
}
