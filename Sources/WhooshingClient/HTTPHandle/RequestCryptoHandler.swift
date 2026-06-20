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
    func send(data: ByteBuffer, context: ChannelHandlerContext, logger: Logger?) -> EventLoopResult<ByteBuffer, Failure>

    /// 解析接收到的响应数据。
    ///
    /// - Parameters:
    ///   - data: 从通道中读取的原始响应字节数据。
    ///   - context: 当前通道上下文。
    /// - Returns: 返回解析出的 HTTP 响应及正文 ByteBuffer 的异步结果。
    func get(data: ByteBuffer, context: ChannelHandlerContext, logger: Logger?) -> EventLoopResult<ByteBuffer, Failure>

    /// 通道连接建立时的钩子方法。
    ///
    /// - Parameter context: 通道上下文。
    /// - Returns: 默认返回已完成的 Future，可用于初始化资源。
    func connectionStart(context: ChannelHandlerContext, logger: Logger?) -> EventLoopResult<Void, Failure>

    /// 通道关闭时的钩子方法。
    ///
    /// - Parameter context: 通道上下文。
    /// - Returns: 默认返回已完成的 Future，可用于释放资源。
    func connectionEnd(context: ChannelHandlerContext, logger: Logger?) -> EventLoopResult<Void, Failure>
}

public extension RequestCryptoIOHandler {
    var isAvaliable: Bool { true }
    func connectionStart(context: ChannelHandlerContext, logger: Logger?) -> EventLoopFuture<Void> { context.eventLoop.makeSucceededVoidFuture() }
    func connectionEnd(context: ChannelHandlerContext, logger: Logger?) -> EventLoopFuture<Void> { context.eventLoop.makeSucceededVoidFuture() }
}

final class RequestCryptoHandler<IOHandler>: ChannelDuplexHandler, RemovableChannelHandler, Sendable where IOHandler: RequestCryptoIOHandler{
    typealias InboundIn = ByteBuffer
    typealias InboundOut = ByteBuffer
    typealias OutboundIn = ByteBuffer
    typealias OutboundOut = ByteBuffer
    
    let logger: Logger?
    let ioHandler: IOHandler
    
    @frozen
    public enum Errcase: String, ErrList {
        case upstreamFailure = "上游错误"
        case internalFailure = "内部错误"
    }

    init(logger: Logger?, ioHandler: IOHandler) {
        self.ioHandler = ioHandler
        self.logger = logger
    }
    
    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        self.logger?.debug("Channel 读取数据", metadata: ["data": .string(data.description)])
        guard ioHandler.isAvaliable else {
            self.logger?.debug("Channel 不可用")
            return
        }
        let buffer = unwrapOutboundIn(data)
        self.logger?.debug("要读取的密文数据", metadata: ["buffer": .stringConvertible(buffer)])
        let loopBound = context.loopBound
        ioHandler.get(data: buffer, context: context, logger: logger).whenComplete { res in
            switch res {
            case .success(let plain):
                self.logger?.debug("buffer 数据解密成功, flush 明文数据", metadata: ["plain": .stringConvertible(plain)])
                loopBound.value.fireChannelRead(self.wrapOutboundOut(plain))
            case .failure(let err):
                self.errorCaught(context: loopBound.value, error: Errcase.internalFailure.subErr(err))
            }
        }
    }
    
    func write(context: ChannelHandlerContext, data: NIOAny, promise: EventLoopPromise<Void>?) {
        self.logger?.debug("Channel 写入数据", metadata: ["data": .string(data.description)])
        guard ioHandler.isAvaliable else { return }
        let buffer = unwrapInboundIn(data)
        self.logger?.debug("要写入的明文数据", metadata: ["buffer": .stringConvertible(buffer)])
        let loopBound = context.loopBound
        let res = ioHandler.send(data: buffer, context: context, logger: logger).wrapped.flatMap { cipher in
            self.logger?.debug("buffer 数据加密完成，flush 密文数据", metadata: ["cipher": .stringConvertible(cipher)])
            return loopBound.value.writeAndFlush(self.wrapOutboundOut(cipher))
        }
        
        if let p = promise {
            res.cascade(to: p)
        }
    }
    
    func channelRegistered(context: ChannelHandlerContext) {
        self.logger?.debug("Channel 将注册", metadata: ["channel": .stringConvertible(context.channel.clientAddrInfo)])
        context.fireChannelRegistered()
        let loopBound = context.loopBound
        ioHandler.connectionStart(context: context, logger: logger).whenFailure { err in
            self.errorCaught(context: loopBound.value, error: Errcase.internalFailure.subErr(err))
        }
    }
    
    func channelUnregistered(context: ChannelHandlerContext) {
        self.logger?.debug("Channel 将注销", metadata: ["channel": .stringConvertible(context.channel.clientAddrInfo)])
        context.fireChannelUnregistered()
        let loopBound = context.loopBound
        ioHandler.connectionEnd(context: context, logger: logger).whenFailure { err in
            self.errorCaught(context: loopBound.value, error: Errcase.internalFailure.subErr(err))
        }
    }
    
    func errorCaught(context: ChannelHandlerContext, error: any Error) {
        if let err = error as? Errcase.ErrType {
            context.fireErrorCaught(err)
        } else {
            let err = Errcase.upstreamFailure.subErr(error)
            context.fireErrorCaught(err)
        }
    }
}
