import Foundation
import NIOConcurrencyHelpers
import ErrorHandle
import LoggingAdvanced

/// 一个支持顺序生成固定数量 `ProgressContext` 的序列，用于模拟或追踪迭代任务进度。
///
/// 可以使用 for-in loop 进行遍历操作:
///
/// 提供 数据块大小 以及 总数据大小 以分配 Progress。例如，以下表示该分配进度的总大小为
///  8KB，且以 1KB 的小块为一步
///
/// ```swift
/// for ctx in Progress(chunk: 1024, bytes: 8192) {
///     print(ctx)              // 打印出该 progress 的详细信息
///     print(ctx.index)        // 从 0...7
///     print(ctx.curBytes)     // 依次打印 1024, 2048, 3072 ... 8192
///     print(ctx.bytes)        // 每次打印 1024
///     print(...)
///     // 进行一些数据生成操作
/// }
/// ```
///
/// 也可 提供 数据块个数 以及 数据块大小 以分配 Progress。以下分配的进度表示该分配进度的
/// 数据块(执行的步数)数量为 10 个，且每一步的数据大小为 512，因此总大小将为
/// 512 Bytes * 10 Pieces = 5120 Bytes
///
/// ```swift
/// for ctx in Progress(pieces: 10, chunk: 512) {
///     print(ctx)              // 打印出该 progress 的详细信息
///     print(ctx.index)        // 从 0...9
///     print(ctx.curBytes)     // 依次打印 512, 1024, 1536 ... 5120
///     print(ctx.bytes)        // 每次打印 512
///     print(...)
///     // 进行一些数据生成操作
/// }
/// ```
///
/// 或者 提供 数据块个数 以及 总数据大小 以分配 Progress。以下分配的进度表示该分配进度的
/// 数据块(执行的步数)数量为 4 个，数据的总大小为 2KB
///
/// ```swift
/// for ctx in Progress(pieces: 4, bytes: 2048) {
///     print(ctx)              // 打印出该 progress 的详细信息
///     print(ctx.index)        // 从 0...3
///     print(ctx.curBytes)     // 依次打印 512, 1024, 1536, 2048
///     print(ctx.bytes)        // 每次打印 512
///     print(...)
///     // 进行一些数据生成操作
/// }
/// ```
///
/// 无需担心如果总大小无法被步数或数据大小整除的情况。若总大小并非数据大小的整倍数，Progress 也会
/// 正确处理每次进度的大小，会将余数分配最后一个 progress 中
///
/// ```swift
/// for ctx in try? Progress(pieces: 5, bytes: 5513) {
///     print(ctx)              // 打印出该 progress 的详细信息
///     print(ctx.index)        // 从 0...4
///     print(ctx.curBytes)     // 依次打印 1378, 2756, 4134, 5512, 5513
///     print(ctx.bytes)        // 依次打印 1378, 1378, 1378, 1378, 1
///     print(...)
///     // 进行一些数据生成操作
/// }
/// ```
///
/// - Warning: 使用指定 总大小 和 块数 的初始方法被认为是不安全的，见函数 `init(pieces:, bytes:, allowLower:)`
@frozen
public struct Progress: Sequence {
    public typealias Element = ProgressContext
    
    @usableFromInline
    let chunk: UInt
    @usableFromInline
    let total: UInt
    
    /// 提供 数据块大小 以及 总数据大小 以分配 Progress
    ///
    /// - Parameters:
    ///   - chunk: 数据块的大小，以字节为单位
    ///   - bytes: 总数据的大小
    @inlinable
    public init(chunk: UInt, bytes: UInt) {
        self.chunk = chunk
        self.total = bytes
    }
    
    /// 提供 数据块个数 以及 数据块大小 以分配 Progress
    ///
    /// - Parameters:
    ///   - pieces: 数据块的个数
    ///   - bytes: 数据块的大小，以字节为单位
    @inlinable
    public init(pieces: UInt, chunk: UInt) {
        self.chunk = chunk
        self.total = pieces * chunk
    }
    
    /// 提供 数据块个数 以及 总数据大小 以分配 Progress
    ///
    /// - Parameters:
    ///   - pieces: 数据块的个数
    ///   - bytes: 总数据的大小
    ///   - allowLower: 是否允许分割数小于所指定的值
    /// - Throws:
    ///   - inputIllegal: 输入非法，当 pieces == 0 时触发
    ///   - pieceFailed: 分片失败，当 allowLower = false，且无法保证按 pieces 数量分配时触发
    ///
    /// 自动切割数据块，若总大小非个数的倍数，会自动切分分配，例如：总大小 5013，
    /// 个数为 5，则每次的数据大小为 1253, 1253, 1253, 1253, 1
    ///
    /// - Warning: 若总大小非个数的倍数，则
    /// 实际进行的数据块的个数可能 = 所指定的个数 - 1。例如，总大小为 600，
    /// 数据块个数为 7，则数据块将会以每步 100 的大小进行，因此只会进行 6 步。另外，所
    /// 输入的数据块个数不可等于 0。因此使用该函数有一定的风险
    @inlinable
    public static func new(pieces: UInt, bytes: UInt, allowLower: Bool = false) -> Res<Self, Errcase> {
        .init { () throws(Errcase.ErrType) in
            try Self.init(pieces: pieces, bytes: bytes, allowLower: allowLower)
        }
    }
    
    @inlinable
    public init(pieces: UInt, bytes: UInt, allowLower: Bool = false) throws(BscError<Errcase>) {
        guard pieces != 0 else {
            throw Errcase.inputIllegal.d("不接受 0 个数据块的分割方式")
        }
        
        if bytes % pieces == 0 {
            self.chunk = bytes / pieces
        } else {
            if allowLower == false, bytes % (pieces - 1) == 0{
                throw Errcase.pieceFailed.d("预计分片为 \(bytes) 块，但只能分为 \(bytes - 1) 块")
            }
            self.chunk = bytes / (pieces - 1)
        }
        self.total = bytes
    }
    
    @frozen
    public enum Errcase: String, ErrList {
        public var domain: String { "woo.sys.server.progress.err" }
        case inputIllegal = "输入非法"
        case pieceFailed = "进度分片失败"
    }

    @frozen
    public struct Iterator: IteratorProtocol {
        @usableFromInline
        private(set) var temp: ProgressContext?
        @usableFromInline
        let chunk: Int

        @usableFromInline
        init(chunk: UInt, total: UInt) {
            self.chunk = Int(chunk)
            guard total > 0 else { self.temp = nil; return }
            self.temp = .init(index: 0, bytes: self.chunk, curBytes: self.chunk, totalBytes: Int(total))
        }

        @inlinable
        public mutating func next() -> ProgressContext? {
            guard let current = temp else { return nil }
            if current.done {
                temp = nil
                return current
            }
            let remains = current.totalBytes! - current.curBytes
            let c = chunk < remains ? chunk : remains
            temp = current.next(c, done: (remains - c) == 0)
            return current
        }
    }

    @inlinable
    public func makeIterator() -> Iterator {
        Iterator(chunk: chunk, total: total)
    }
}

/// 一个用于发送和读取异步进度的类，发送方调用 `sendProgress(_:)`，读取方通过 `for await` 获取进度。
///
/// 适用于文件传输、数据处理等异步任务，具备类 `AsyncStream` 的生产者-消费者语义。
public final class AsyncProgress: AsyncSequence, @unchecked Sendable {
    public typealias Failure = Error
    public typealias AsyncIterator = AsyncMapSequence<Base, ProgressContext>.AsyncIterator
    public typealias Element = ProgressContext
    public typealias Base = AsyncThrowingStream<Int, Error>
    
    @inlinable
    public var totalBytes: Int? {
        set { lock.withLock { progress = progress.totalBytes(newValue) } }
        get { lock.withLock { progress.totalBytes } }
    }
    
    @usableFromInline
    let continuation: Base.Continuation
    @usableFromInline
    let stream: Base
    @usableFromInline
    private(set) var progress: ProgressContext
    @usableFromInline
    let lock = NIOLock()
    
    @inlinable
    public init() {
        (self.stream, self.continuation) = Base.makeStream()
        progress = .init(index: -1)
    }
    
    @inlinable
    public convenience init(_ closure: @escaping @Sendable (ProgressContext) -> Void) {
        self.init()
        Task {
            for try await ctx in self {
                closure(ctx)
            }
        }
    }
    
    /// 向进度通道发送一条新的进度信息
    /// - Parameter byte: 当前处理的数据大小
    @inlinable
    public func sendProgress(_ byte: Int) {
        continuation.yield(byte)
    }

    /// 标记进度结束，关闭通道
    @inlinable
    public func finish(throwing error: Error? = nil) {
        continuation.finish(throwing: error)
    }
    
    @inlinable
    public func makeAsyncIterator() -> AsyncIterator {
        stream.map { curChunk in
            self.progress = self.progress.next(curChunk, done: self.progress.curBytes + curChunk == self.progress.totalBytes)
            return self.progress
        }.makeAsyncIterator()
    }
}

/// 表示某个数据传输或处理任务的进度上下文。
///
/// `ProgressContext` 用于追踪任务的当前进度，包括已传输字节数、总字节数、耗时、速度等信息，
/// 同时携带与该任务相关的通道信息和用户自定义的响应值。
@frozen
public struct ProgressContext: Sendable, CustomStringConvertible, Loggerable {
    
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
    
    @inlinable
    public init(index: Int = 0, done: Bool = false, bytes: Int = 0, curBytes: Int = 0, totalBytes: Int? = nil, startDate: Date = Date()) {
        self.index = index
        self.done = done
        self.curBytes = curBytes
        self.totalBytes = totalBytes
        self.startDate = startDate
        self.bytes = bytes
    }

    /// 当前字节传输进度（0~1），如果 `totalBytes` 未知或为 0，则为 `nil`。
    @inlinable
    public var bytesPersentage: Double? {
        if let tb = totalBytes, tb > 0 {
            return Double(curBytes) / Double(tb)
        }
        return nil
    }

    /// 格式化的字节传输百分比字符串（例如 "68.2%"），如果无法计算则返回 `"~%"`。
    @inlinable
    public var bytesPersentageStr: String {
        (bytesPersentage == nil ? "~" : String(Float(Int(bytesPersentage! * 100 * 100) / 100))) + "%"
    }

    /// 格式化的总字节数字符串（例如 "12.3 MB"），如果未知则返回 `"~B"`。
    @inlinable
    public var totalBytesStr: String {
        totalBytes == nil ? "~B" : ChunkTool.formatByteSize(totalBytes!)
    }

    /// 格式化的当前字节数字符串（例如 "3.5 MB"）。
    @inlinable
    public var curBytesStr: String {
        ChunkTool.formatByteSize(curBytes)
    }

    /// 当前的传输速度（字节每秒），如果耗时为 0 则为 `nil`。
    @inlinable
    public var speed: Double? {
        let timeCost = Double(timeCost)
        if timeCost > 0 {
            return (Double(curBytes) / timeCost)
        } else {
            return nil
        }
    }

    /// 格式化的传输速度字符串（例如 "1.2MB/s"），如果无法计算则返回 `"~B/s"`。
    @inlinable
    public var speedStr: String {
        if let speed = self.speed {
            return ChunkTool.formatByteSize(.init(speed)) + "/s"
        } else {
            return "~B/s"
        }
    }

    /// 当前任务已耗费的时间字符串（单位：秒）。
    @inlinable
    public var timeCost: TimeInterval {
        Date().timeIntervalSince(startDate)
    }
    
    @inlinable
    public var timeCostStr: String {
        String(format: "%.6fs", self.timeCost)
    }

    /// 返回当前进度上下文的字符串描述，方便调试和日志记录。
    @inlinable
    public var description: String {
        "\(index): 字节进度: \(bytesPersentageStr) [\(curBytesStr)(\(curBytes))-\(totalBytesStr)(\(totalBytes == nil ? "~" : String(totalBytes!)))], 大小: \(bytes), 完成: \(done), 耗时: \(timeCostStr), 速度: \(speedStr)"
    }
    
    @inlinable
    public var summaryDescription: String {
        "\(index): \(bytesPersentageStr)-\(totalBytesStr), \(timeCostStr)"
    }
    
    @inlinable
    public func totalBytes(_ totalBytes: Int?) -> Self{
        ProgressContext(index: index, done: done, bytes: bytes, curBytes: curBytes, totalBytes: totalBytes, startDate: startDate)
    }
    
    @inlinable
    public func done(_ done: Bool) -> Self{
        ProgressContext(index: index, done: done, bytes: bytes, curBytes: curBytes, totalBytes: totalBytes, startDate: startDate)
    }
    
    @inlinable
    public func next(_ dataSize: Int, done: Bool = false) -> Self {
        .init(index: index + 1, done: done, bytes: dataSize, curBytes: curBytes + dataSize, totalBytes: totalBytes, startDate: startDate)
    }
}
