import Cryptos
import ErrorHandle
import NIOConcurrencyHelpers
import NIO
import NIOExtras
import NIOAdvanced
import NIOPosix
import Logging
import Foundation
import AsyncHTTPClient
import NIOHTTP1

open class ReqClient<IOHandler>: @unchecked Sendable where IOHandler: RequestCryptoIOHandler {
    public let eventLoop: EventLoop
    public let fileEventLoop: EventLoop
    public let logger: Logger?
    public let byteBufferAllocator: ByteBufferAllocator
    public var ioHandler: IOHandler!
    public let storage: SendableStorage = .init()
    public internal(set) var channelPool: SendableDictionary<String, Channel> = .init()
    public weak var channel: Channel? {
        if let channel = __channel, channel.isActive { return channel }
        return nil
    }
    
    @usableFromInline
    private(set) weak var __channel: Channel?
    @usableFromInline
    private(set) var lock: NIOLock = .init()
    @usableFromInline
    let removableHandlerNames: [String] = [
        "Whooshing Crypto Handler",
        "NIO HTTPRequestEncoder",
        "NIO HTTPResponseDecoder",
        "NIO HTTPRequestHeadersValidator",
        "Whooshing Request Wrapper Handler"
    ]
    
    @inlinable
    public required init(eventLoop: EventLoop, logger: Logger? = nil, byteBufferAllocator: ByteBufferAllocator, ioHandler: IOHandler? = nil) {
        self.eventLoop = eventLoop
        self.fileEventLoop = eventLoop.next()
        self.logger = logger
        self.byteBufferAllocator = byteBufferAllocator
        self.ioHandler = ioHandler
    }
}
 
extension ReqClient {
    
    @frozen
    public enum Errcase: String, ErrList {
        case requestFormatError = "请求格式有误"
        case requestBodyTooLarge = "请求的内容过大"
        case requestParseFailed = "服务器响应头解包时出错"
        case requestDomainParseFailed = "域名解析失败"
        case tcpHandlerInitialFailed = "TCP 中间流处理器初始化失败"
        case tcpHandlerRemoveFailed = "TCP 中间流处理器移除失败"
        case tcpSocketConnectFailed = "TCP 连接失败"
        case tcpSendFailed = "TCP 通道写入数据失败"
        case tcpHandlerFailed = "TCP 中间流处理器处理失败"
    }

    public func makeChannel(url: WebURI) -> EventLoopRes<(Channel, RequestWrapperHandler, domain: String?), Errcase> {
        
        guard [.http, .https].contains(url.scheme) else {
            return eventLoop.makeFailedResult(Errcase.requestFormatError, "预期请求协议为 http 或 https，但得到 \(url.scheme)")
        }

        let port: Int
        let isDomainHost = url.isDomainHost()
        if isDomainHost {
            port = url.port ?? (url.scheme == .https ? 443 : 20002)
        } else {
            guard let p = url.port else {
                return eventLoop.makeFailedResult(Errcase.requestFormatError, "无法获取 Port")
            }
            port = p
        }

        let id = "\(url.host):\(port)"

        if let channel = self.channelPool[id], channel.isActive {
            return channel.pipeline.handler(type: RequestWrapperHandler.self).flatMap { handler in
                self.__channel = channel
                return channel.eventLoop.makeSucceededFuture((channel, handler, isDomainHost ? url.host : nil))
            }.withError(Errcase.tcpHandlerInitialFailed)
        }
        
        let cryptoHandler = RequestCryptoHandler(logger: logger, ioHandler: ioHandler)
        let wrapperHandler = RequestWrapperHandler(logger: logger)

        let bootstrap = ClientBootstrap(group: self.eventLoop)
            .channelInitializer { channel in
                channel.pipeline.addHandlers([
                    NIOCloseOnErrorHandler(),
                    RequestBackPressureHandler(),
                    LengthFieldPrepender(lengthFieldLength: .eight, lengthFieldEndianness: .big),
                    ByteToMessageHandler(LengthFieldBasedFrameDecoder(lengthFieldLength: .eight, lengthFieldEndianness: .big))
                ]).flatMap {
                    channel.eventLoop.makeFutureWithTask {
                        let handlers: [ChannelHandler & Sendable] = [
                            cryptoHandler,
                            HTTPRequestEncoder(configuration: .init()),
                            ByteToMessageHandler(HTTPResponseDecoder(leftOverBytesStrategy: .dropBytes)),
                            NIOHTTPRequestHeadersValidator(),
                            wrapperHandler
                        ]
                        for (i, handler) in handlers.enumerated() {
                            try await channel.pipeline.addHandler(handler, name: self.removableHandlerNames[i])
                        }
                    }
                }
            }
            .channelOption(.socketOption(.tcp_nodelay), value: 1)
            .channelOption(.socketOption(.so_reuseaddr), value: 1)
            .channelOption(.maxMessagesPerRead, value: 1)
            .channelOption(.autoRead, value: false)

        return bootstrap.connect(host: url.host, port: port).map { channel in
            self.channelPool[id] = channel
            self.__channel = channel
            return (channel, wrapperHandler, isDomainHost ? url.host : nil)
        }.withError(Errcase.tcpHandlerInitialFailed)
    }

    public func send(
        _ client: HTTPRequest,
        channel: Channel,
        handler: RequestWrapperHandler
    ) -> EventLoopRes<HTTPResponse, Errcase> {
        let promise: EventLoopTarget<HTTPResponse, RequestWrapperHandler.Errcase.ErrType> = channel.eventLoop.makeTarget(of: HTTPResponse.self)
        handler.promise = promise
        return channel.writeAndFlush(client)
            .withError(Errcase.tcpSendFailed)
            .flatMapError
        { err in
            self.logger?.warning("\(err)")
            promise.fail(RequestWrapperHandler.Errcase.cancelled.d())
            return channel.eventLoop.makeFailedResult(err)
        }.flatMap {
            promise.futureResult.errCast(Errcase.tcpHandlerFailed)
        }
    }

    public func closeAll() async {
        for (_, channel) in channelPool {
            try? await channel.close(mode: .all)
        }
        channelPool.removeAll()
    }
    
    public func removeHTTPHandlers(in eventLoop: any EventLoop) -> EventLoopRes<Void, Errcase> {
        eventLoop.makeResultWithTask {  () throws(BscError<Errcase>) in
            try await self.removeHTTPHandlers().get()
        }
    }
    
    public func removeHTTPHandlers() async -> Res<Void, Errcase> {
        await .async {
            guard let channel = self.channel else { return }
            for name in self.removableHandlerNames {
                try await required(throws: Errcase.tcpHandlerRemoveFailed) {
                    try await channel.pipeline.removeHandler(name: name)
                }
            }
        }
    }
}
