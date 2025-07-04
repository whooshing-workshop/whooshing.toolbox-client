import NIOCore
import Foundation

/// 提供对 ByteBuffer 分片大小的工具支持，包含最大分块大小、大小格式化、EOF 标识等常用工具函数。
@frozen
public struct ChunkTool {
    /// 将字节数格式化为易读的字符串（带单位），如 "1.23 MB"
    /// - Parameter bytes: 原始字节数
    /// - Returns: 格式化结果字符串
    @inlinable
    public static func formatByteSize(_ bytes: Int) -> String {
        let units = ["Bytes", "KB", "MB", "GB", "TB", "PB", "EB"]
        
        var size = Double(bytes)
        var unitIndex = 0
        
        while size >= 1024 && unitIndex < units.count - 1 {
            size /= 1024
            unitIndex += 1
        }
        
        return String(format: "%.2f %@", size, units[unitIndex])
    }

    /// 拼接两个 ByteBuffer，并返回拼接后的新 Buffer
    /// - Parameters:
    ///   - buffer1: 第一个缓冲区（会被读取）
    ///   - buffer2: 第二个缓冲区（会被读取）
    /// - Returns: 拼接后的新 ByteBuffer 实例
    @inlinable
    public static func concatenateBuffers(_ buffer1: inout ByteBuffer, _ buffer2: inout ByteBuffer) -> ByteBuffer {
        let totalSize = buffer1.readableBytes + buffer2.readableBytes
        var resultBuffer = ByteBufferAllocator().buffer(capacity: totalSize)
        resultBuffer.writeBuffer(&buffer1)
        resultBuffer.writeBuffer(&buffer2)
        return resultBuffer
    }
}
