import Cryptos
import ErrorHandle
import NIOCore
import Logging
import NIOAdvanced

// 用于处理请求客户端与服务器之间的加密机制

/// 定义了处理 HTTP 请求输入输出的接口协议，支持发送请求与接收响应的异步操作。
/// 可用于实现加密通信、流式传输、或自定义的请求/响应处理器。
public protocol RequestCryptoIOHandler: Sendable {
    
    associatedtype Failure: Error
    
    var isAvaliable: Bool { get }
    /// 发送一个 HTTP 请求的数据块。
    ///
    /// - Parameters:
    ///   - data: 原始 HTTP 请求数据。
    ///   - context: 当前 NIO 通道处理上下文。
    /// - Returns: 返回包含最终发送 ByteBuffer 的异步结果。
    func send(data: ByteBuffer, context: ChannelHandlerContext) -> EventLoopResult<ByteBuffer, Failure>

    /// 解析接收到的响应数据。
    ///
    /// - Parameters:
    ///   - data: 从通道中读取的原始响应字节数据。
    ///   - context: 当前通道上下文。
    /// - Returns: 返回解析出的 HTTP 响应及正文 ByteBuffer 的异步结果。
    func get(data: ByteBuffer, context: ChannelHandlerContext) -> EventLoopResult<ByteBuffer, Failure>

    /// 通道连接建立时的钩子方法。
    ///
    /// - Parameter context: 通道上下文。
    /// - Returns: 默认返回已完成的 Future，可用于初始化资源。
    func connectionStart(context: ChannelHandlerContext) -> EventLoopResult<Void, Failure>

    /// 通道关闭时的钩子方法。
    ///
    /// - Parameter context: 通道上下文。
    /// - Returns: 默认返回已完成的 Future，可用于释放资源。
    func connectionEnd(context: ChannelHandlerContext) -> EventLoopResult<Void, Failure>
}

public extension RequestCryptoIOHandler {
    var isAvaliable: Bool { true }
    func connectionStart(context: ChannelHandlerContext) -> EventLoopFuture<Void> { context.eventLoop.makeSucceededVoidFuture() }
    func connectionEnd(context: ChannelHandlerContext) -> EventLoopFuture<Void> { context.eventLoop.makeSucceededVoidFuture() }
}

final class RequestCryptoHandler<IOHandler>: ChannelDuplexHandler, RemovableChannelHandler, @unchecked Sendable where IOHandler: RequestCryptoIOHandler{
    typealias InboundIn = ByteBuffer
    typealias InboundOut = ByteBuffer
    typealias OutboundIn = ByteBuffer
    typealias OutboundOut = ByteBuffer
    
    let logger: Logger?
    let ioHandler: IOHandler
    
    @frozen
    public enum Errcase: String, ErrList {
        case internalFailure = "内部错误"
    }

    init(logger: Logger?, ioHandler: IOHandler) {
        self.ioHandler = ioHandler
        self.logger = logger
    }
    
    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        guard ioHandler.isAvaliable else { return }
        let buffer = unwrapOutboundIn(data)
        ioHandler.get(data: buffer, context: context).whenComplete { res in
            switch res {
            case .success(let response): context.fireChannelRead(self.wrapOutboundOut(response))
            case .failure(let err): self.errorHappend(context: context, error: Errcase.internalFailure.subErr(err))
            }
        }
    }
    
    func write(context: ChannelHandlerContext, data: NIOAny, promise: EventLoopPromise<Void>?) {
        guard ioHandler.isAvaliable else { return }
        let buffer = unwrapInboundIn(data)
        let res = ioHandler.send(data: buffer, context: context).wrapped.flatMap { res in
            context.writeAndFlush(self.wrapOutboundOut(res))
        }
        
        if let p = promise {
            res.cascade(to: p)
        }
    }
    
    func logIfTracing(prefix: String, context: ChannelHandlerContext, size: Int) {
        if let logger = self.logger, logger.logLevel == .trace {
            self.logger?.trace("\(prefix): \(context.channel.clientAddrInfo), 大小: \(ChunkTool.formatByteSize(size))")
        }
    }
    
    func channelRegistered(context: ChannelHandlerContext) {
        context.fireChannelRegistered()
        ioHandler.connectionStart(context: context).whenFailure { err in
            self.errorHappend(context: context, error: Errcase.internalFailure.subErr(err))
        }
    }
    
    func channelUnregistered(context: ChannelHandlerContext) {
        context.fireChannelUnregistered()
        ioHandler.connectionEnd(context: context).whenFailure { err in
            self.errorHappend(context: context, error: Errcase.internalFailure.subErr(err))
        }
    }
    
    func errorHappend(context: ChannelHandlerContext, error: Errcase.ErrType) {
        logger?.warning("\(error)")
        context.fireErrorCaught(error)
    }
}
