import Cryptos
import ErrorHandle
import NIOCore
import NIOConcurrencyHelpers
import Foundation
import Logging
import AsyncHTTPClient

// 用于处理请求客户端与服务器之间的加密机制

/// 定义了处理 HTTP 请求输入输出的接口协议，支持发送请求与接收响应的异步操作。
/// 可用于实现加密通信、流式传输、或自定义的请求/响应处理器。
public protocol RequestCryptoIOHandler: Sendable {

    /// 发送一个 HTTP 请求的数据块。
    ///
    /// - Parameters:
    ///   - request: 原始 HTTP 请求对象。
    ///   - dataChunk: 要发送的当前数据块。
    ///   - context: 当前 NIO 通道处理上下文。
    ///   - allocator: 用于分配 ByteBuffer 的分配器。
    ///   - streaming: 是否为流式发送；true 表示还有更多数据后续发送。
    /// - Returns: 返回包含最终发送 ByteBuffer 的异步结果。
    func send(data: ByteBuffer, context: ChannelHandlerContext) -> EventLoopFuture<ByteBuffer>

    /// 解析接收到的响应数据。
    ///
    /// - Parameters:
    ///   - response: 从通道中读取的原始响应字节数据。
    ///   - bufferStrategy: 缓冲策略，指示是收集全部数据还是流式处理。
    ///   - context: 当前通道上下文。
    ///   - streaming: 是否为流式接收。
    /// - Returns: 返回解析出的 HTTP 响应及正文 ByteBuffer 的异步结果。
    func get(data: ByteBuffer, context: ChannelHandlerContext) -> EventLoopFuture<ByteBuffer>

    /// 通道连接建立时的钩子方法。
    ///
    /// - Parameter context: 通道上下文。
    /// - Returns: 默认返回已完成的 Future，可用于初始化资源。
    func connectionStart(context: ChannelHandlerContext) -> EventLoopFuture<Void>

    /// 通道关闭时的钩子方法。
    ///
    /// - Parameter context: 通道上下文。
    /// - Returns: 默认返回已完成的 Future，可用于释放资源。
    func connectionEnd(context: ChannelHandlerContext) -> EventLoopFuture<Void>
}

public extension RequestCryptoIOHandler {
    func connectionStart(context: ChannelHandlerContext) -> EventLoopFuture<Void> { context.eventLoop.makeSucceededVoidFuture() }
    func connectionEnd(context: ChannelHandlerContext) -> EventLoopFuture<Void> { context.eventLoop.makeSucceededVoidFuture() }
}

final class RequestCryptoHandler: ChannelDuplexHandler, RemovableChannelHandler, @unchecked Sendable {
    typealias InboundIn = ByteBuffer
    typealias InboundOut = ByteBuffer
    typealias OutboundIn = ByteBuffer
    typealias OutboundOut = ByteBuffer

    private let logger: Logger?
    private let ioHandler: RequestCryptoIOHandler

    init(logger: Logger?, ioHandler: RequestCryptoIOHandler) {
        self.ioHandler = ioHandler
        self.logger = logger
    }
    
    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        let buffer = unwrapOutboundIn(data)
        ioHandler.get(data: buffer, context: context).whenComplete { res in
            switch res {
            case .success(let response): context.fireChannelRead(self.wrapOutboundOut(response))
            case .failure(let err): self.errorCaught(context: context, error: err)
            }
        }
    }
    
    func write(context: ChannelHandlerContext, data: NIOAny, promise: EventLoopPromise<Void>?) {
        let buffer = unwrapInboundIn(data)
        let res = ioHandler.send(data: buffer, context: context).flatMap { res in
            if buffer.readableBytes > 0 {
                return context.write(self.wrapOutboundOut(res))
            } else {
                context.flush()
                return context.eventLoop.makeSucceededVoidFuture()
            }
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
            self.errorCaught(context: context, error: err)
        }
    }
    
    func channelUnregistered(context: ChannelHandlerContext) {
        context.fireChannelUnregistered()
        ioHandler.connectionEnd(context: context).whenFailure { err in
            self.errorCaught(context: context, error: err)
        }
    }
    
    func errorCaught(context: ChannelHandlerContext, error: Error) {
        logger?.warning("\(error)")
        context.fireErrorCaught(error)
    }

    enum Err: String, ErrList {
        var domain: String { "woo.sys.client.err" }
        case chunkSizeExceed = "流式传输块大小不正确"
    }
}
