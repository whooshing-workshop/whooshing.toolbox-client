import NIOCore
import NIOHTTP1
import NIOConcurrencyHelpers

/// 带有 Backpressure 机制的 Channel 处理器
@usableFromInline
final class RequestBackPressureHandler: ChannelDuplexHandler, @unchecked Sendable {
    @usableFromInline
    typealias InboundIn = ByteBuffer
    @usableFromInline
    typealias OutboundIn = ByteBuffer
    
    @usableFromInline
    var keepRead: Bool {
        get { lock.withLock { __keepRead } }
        set { lock.withLock { __keepRead = newValue } }
    }
    
    @usableFromInline
    let lock = NIOLock()
    @usableFromInline
    private(set) var __keepRead = true
    
    @inlinable
    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        context.fireChannelRead(data)
        if self.keepRead {
            context.read()
        }
    }
    
    @inlinable
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
    
    @inlinable
    init() {}
}
