import NIOCore
import NIOHTTP1
import NIOConcurrencyHelpers

/// 带有 Backpressure 机制的 Channel 处理器
final class RequestBackPressureHandler: ChannelDuplexHandler, @unchecked Sendable {
    typealias InboundIn = ByteBuffer
    typealias OutboundIn = ByteBuffer
    
    var keepRead: Bool {
        get { lock.withLock { __keepRead } }
        set { lock.withLock { __keepRead = newValue } }
    }
    
    private let lock = NIOLock()
    private var __keepRead = true
    
    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        context.fireChannelRead(data)
        if self.keepRead {
            context.read()
        }
    }
    
    func triggerUserOutboundEvent(context: ChannelHandlerContext, event: Any, promise: EventLoopPromise<Void>?) {
        if let status = event as? RequestWrapperHandler.ReadingStatus {
            switch status {
            case .pause:
                keepRead = false
            case .resume:
                keepRead = true
                context.read()
            }
        }
        promise?.succeed()
    }
}
