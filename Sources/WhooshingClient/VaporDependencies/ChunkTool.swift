import NIOCore

/// 提供对 ByteBuffer 分片大小的工具支持，包含最大分块大小、大小格式化、EOF 标识等常用工具函数。
public struct ChunkTool {
    /// Whooshing 最大分块字节数，为 64 KB
    public static var maxChunk: Int { 65536 } // 64 kB

    /// 格式化后的最大分块大小字符串，例如 "64.00 KB"
    public static var maxChunkStr: String { formatByteSize(maxChunk) }

    /// EOF 结束标记（内容为字符串 "EOF"）
    public static let eof = ByteBuffer(string: "EOF")

    /// 将字节数格式化为易读的字符串（带单位），如 "1.23 MB"
    /// - Parameter bytes: 原始字节数
    /// - Returns: 格式化结果字符串
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

    /// 判断指定字节数是否在允许的最大分块范围内
    /// - Parameter bytes: 要检查的字节数
    /// - Returns: 是否小于等于最大分块大小
    public static func isProperSize(bytes: Int) -> Bool { bytes <= maxChunk }

    /// 拼接两个 ByteBuffer，并返回拼接后的新 Buffer
    /// - Parameters:
    ///   - buffer1: 第一个缓冲区（会被读取）
    ///   - buffer2: 第二个缓冲区（会被读取）
    /// - Returns: 拼接后的新 ByteBuffer 实例
    public static func concatenateBuffers(_ buffer1: inout ByteBuffer, _ buffer2: inout ByteBuffer) -> ByteBuffer {
        let totalSize = buffer1.readableBytes + buffer2.readableBytes
        var resultBuffer = ByteBufferAllocator().buffer(capacity: totalSize)
        resultBuffer.writeBuffer(&buffer1)
        resultBuffer.writeBuffer(&buffer2)
        return resultBuffer
    }
}
