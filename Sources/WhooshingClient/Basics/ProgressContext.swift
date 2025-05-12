import Vapor
import Foundation
import NIOCore


/// 数据缓冲策略，用于控制数据如何在处理过程中进行缓存或流式传输。
///
/// `BufferStrategy` 提供两种策略：
/// - `.collect`：一次性收集全部数据后再处理。
/// - `.streaming`：在数据传输过程中进行逐步处理，适合大数据或流式内容。
public enum BufferStrategy: Sendable {
    
    /// 一次性收集所有数据后再统一处理。
    ///
    /// 适用于数据量较小、处理逻辑依赖完整数据的场景。
    case collect

    /// 以流式方式处理数据，边接收边处理。
    ///
    /// - Parameters:
    ///   - totalSize: 预计的数据总大小（单位：字节）。
    ///   - stream: 异步数据处理闭包，接收数据块并处理。见 ``AsyncStreamingDataAction``
    ///
    /// 适用于处理大型文件、实时数据等流式任务。
    case streaming(totalSize: Int, stream: AsyncStreamingDataAction)
}


/// 表示某个数据传输或处理任务的进度上下文。
///
/// `ProgressContext` 用于追踪任务的当前进度，包括已传输字节数、总字节数、耗时、速度等信息，
/// 同时携带与该任务相关的通道信息和用户自定义的响应值。
public struct ProgressContext<Value>: CustomStringConvertible {
    
    /// 当前任务在整个进度列表中的索引编号（适用于分片或批量任务）。
    public let index: Int

    /// 当前任务的数据缓冲区。
    public let data: ByteBuffer

    /// 是否已完成任务。
    public let done: Bool

    /// 当前已传输或处理的字节数。
    public let curBytes: Int

    /// 预计总的字节数，如果未知则为 `nil`。
    public let totalBytes: Int?

    /// 任务开始的时间。
    public let startDate: Date

    /// 与该任务关联的通道（如网络连接、文件流等）。
    public let channel: Channel

    /// 与该进度上下文相关联的用户自定义响应值。
    public let response: Value

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

    /// 与 `totalBytesStr` 相同，用于统一显示总大小。
    public var totalSize: String {
        totalBytes == nil ? "~B" : ChunkTool.formatByteSize(totalBytes!)
    }

    /// 当前的传输速度（字节每秒），如果耗时为 0 则为 `nil`。
    public var speed: Double? {
        Int(timeCost) <= 0 ? nil : (Double(curBytes) / Double(timeCost))
    }

    /// 格式化的传输速度字符串（例如 "1.2 MB/s"），如果无法计算则返回 `"~B/s"`。
    public var speedStr: String {
        speed == nil ? "~B/s" : (ChunkTool.formatByteSize(.init(speed!)) + "/s")
    }

    /// 当前任务已耗费的时间（单位：秒）。
    public var timeCost: TimeInterval {
        Date.now.timeIntervalSince(startDate)
    }

    /// 返回当前进度上下文的字符串描述，方便调试和日志记录。
    public var description: String {
        "Progress(\(index), 字节进度: \(bytesPersentageStr) [\(curBytesStr)(\(curBytes))-\(totalBytesStr)(\(totalBytes == nil ? "~" : String(totalBytes!)))], 数据块: \(data.readableBytes), 完成: \(done), 耗时: \(timeCost)s, 速度: \(speedStr), 值: \(Value.self))"
    }

    /// 创建一个新的 `ProgressContext` 实例，保留原有数据，仅替换 `response`。
    ///
    /// - Parameters:
    ///   - value: 新的响应值。
    /// - Returns: 新的 `ProgressContext`，除了 `response` 外其他内容与当前实例相同。
    public func copy<T>(value: T) -> ProgressContext<T> {
        .init(index: index, data: data, done: done, curBytes: curBytes, totalBytes: totalBytes, startDate: startDate, channel: channel, response: value)
    }
}
