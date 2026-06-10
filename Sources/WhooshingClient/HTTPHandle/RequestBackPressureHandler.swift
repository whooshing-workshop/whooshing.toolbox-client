import NIOCore
import NIOHTTP1
import Logging
import NIOConcurrencyHelpers

/// 带有 Backpressure 机制的 Channel 处理器
final class RequestBackPressureHandler: ChannelDuplexHandler, @unchecked Sendable {
    typealias InboundIn = ByteBuffer
    typealias OutboundIn = ByteBuffer
    
    let logger: Logger?
    
    @inlinable
    init(logger: Logger?) {
        self.logger = logger
    }
    
    var keepRead: Bool {
        get { lock.withLock { __keepRead } }
        set { lock.withLock { __keepRead = newValue } }
    }
    
    let lock = NIOLock()
    private(set) var __keepRead = true
    
    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        self.logger?.debug("Channel 读取数据", metadata: ["data": .string(data.description)])
        context.fireChannelRead(data)
        if self.keepRead {
            context.read()
        }
    }
    
    func triggerUserOutboundEvent(context: ChannelHandlerContext, event: Any, promise: EventLoopPromise<Void>?) {
        if let status = event as? RequestWrapperHandler.ReadingStatus {
            self.logger?.debug("背压状态变更事件触发", metadata: ["event": .stringConvertible(status)])
            switch status {
            case .pause:
                self.logger?.debug("背压状态变更为 false")
                keepRead = false
            case .resume:
                self.logger?.debug("背压状态变更为 true")
                keepRead = true
                context.read()
            }
        }
        promise?.succeed()
    }
}
