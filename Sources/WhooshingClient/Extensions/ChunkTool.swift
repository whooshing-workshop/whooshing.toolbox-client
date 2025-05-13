#if !WHOOSHING_VAPOR

import NIOCore

public struct ChunkTool {
    public static var maxChunk: Int { 65536 } // 64 kB

    public static var maxChunkStr: String { formatByteSize(maxChunk) }

    public static let eof = ByteBuffer(string: "EOF")

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

    public static func isProperSize(bytes: Int) -> Bool { bytes <= maxChunk }

    public static func concatenateBuffers(_ buffer1: inout ByteBuffer, _ buffer2: inout ByteBuffer) -> ByteBuffer {
        let totalSize = buffer1.readableBytes + buffer2.readableBytes
        var resultBuffer = ByteBufferAllocator().buffer(capacity: totalSize)
        resultBuffer.writeBuffer(&buffer1)
        resultBuffer.writeBuffer(&buffer2)
        return resultBuffer
    }
}

#endif
