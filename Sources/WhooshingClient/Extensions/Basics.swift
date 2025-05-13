import DataConvertable
import Foundation
import Cryptos
import NIOCore
import NIOFoundationCompat

extension ChannelHandlerContext: @retroactive @unchecked Sendable {}

extension ByteBuffer: @retroactive ThrowableDataConvertable {}
extension ByteBuffer: @retroactive SafeDataConvertable {
    public func data() -> Data { .init(buffer: self) }
}

public extension URL {
    func toUri(with path: String) -> WebURI { .init(stringLiteral: self.absoluteString + path) }
}

public func streamingHandle(
    chunkData: inout ByteBuffer,
    context: ChannelHandlerContext,
    bufferStrategy: BufferStrategy,
    dic: SendableDictionary<ObjectIdentifier, ByteBuffer>, 
    streaming: Bool) -> EventLoopFuture<ByteBuffer?> 
{
    if case .collect = bufferStrategy {
        let id = ObjectIdentifier(context.channel)
        if streaming {
            if var data = dic[id] {
                data.writeBuffer(&chunkData)
                dic[id] = data
            } else {
                dic[id] = chunkData
            }
            return context.eventLoop.makeSucceededFuture(nil)
        } else {
            var data = dic[id]
            dic[id] = nil
            return context.eventLoop.makeSucceededFuture(data == nil ? chunkData : { data!.writeBuffer(&chunkData); return data! }())
        }
    } else {
        return context.eventLoop.makeSucceededFuture(nil)
    }
}
