import Cryptos
import ErrorHandle
import NIOConcurrencyHelpers
import NIO
import NIOExtras
import NIOPosix
import Logging
import Foundation
import AsyncHTTPClient
import NIOHTTP1

open class ReqClient: @unchecked Sendable {
    public let eventLoop: EventLoop
    public let fileEventLoop: EventLoop
    public let logger: Logger?
    public let byteBufferAllocator: ByteBufferAllocator
    public var ioHandler: RequestCryptoIOHandler!
    public let storage: SendableStorage = .init()
    public internal(set) var channelPool: SendableDictionary<String, Channel> = .init()
    public weak var channel: Channel? {
        if let channel = __channel, channel.isActive { return channel }
        return nil
    }
    
    private weak var __channel: Channel?
    private var lock: NIOLock = .init()
    private let removableHandlerNames: [String] = [
        "Whooshing Crypto Handler",
        "NIO HTTPRequestEncoder",
        "NIO HTTPResponseDecoder",
        "NIO HTTPRequestHeadersValidator",
        "Whooshing Request Wrapper Handler"
    ]
    
    public required init(eventLoop: EventLoop, logger: Logger? = nil, byteBufferAllocator: ByteBufferAllocator, ioHandler: RequestCryptoIOHandler? = nil) {
        self.eventLoop = eventLoop
        self.fileEventLoop = eventLoop.next()
        self.logger = logger
        self.byteBufferAllocator = byteBufferAllocator
        self.ioHandler = ioHandler
    }

    public func makeChannel(url: WebURI) -> EventLoopFuture<(Channel, RequestWrapperHandler, domain: String?)> {
        
        guard [.http, .https].contains(url.scheme) else {
            return eventLoop.makeFailedFuture(Err.requestFormatError.d("预期请求协议为 http 或 https，但得到 \(url.scheme)", 13052))
        }

        let port: Int
        let isDomainHost = url.isDomainHost()
        if isDomainHost {
            port = url.port ?? (url.scheme == .https ? 443 : 20002)
        } else {
            guard let p = url.port else {
                return eventLoop.makeFailedFuture(Err.requestFormatError.d("无法获取 Port", 10081))
            }
            port = p
        }

        let id = "\(url.host):\(port)"

        if let channel = self.channelPool[id], channel.isActive {
            return channel.pipeline.handler(type: RequestWrapperHandler.self).flatMap { handler in
                self.__channel = channel
                return channel.eventLoop.makeSucceededFuture((channel, handler, isDomainHost ? url.host : nil))
            }
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
        }
    }

    public func send(
        _ client: HTTPRequest,
        channel: Channel,
        handler: RequestWrapperHandler
    ) -> EventLoopFuture<HTTPResponse> {
        let promise = channel.eventLoop.makePromise(of: HTTPResponse.self)
        handler.promise = promise
        return channel.writeAndFlush(client).flatMapError { err in
            self.logger?.warning("\(err)")
            promise.fail(err)
            return channel.eventLoop.makeFailedFuture(err)
        }.flatMap {
            promise.futureResult
        }
    }

    public func closeAll() async {
        for (_, channel) in channelPool {
            try? await channel.close(mode: .all)
        }
        channelPool.removeAll()
    }
    
    public func removeHTTPHandlers(in eventLoop: any EventLoop) -> EventLoopFuture<Void> {
        eventLoop.makeFutureWithTask {
            try await self.removeHTTPHandlers()
        }
    }
    
    public func removeHTTPHandlers() async throws {
        guard let channel = self.channel else { return }
        for name in self.removableHandlerNames {
            try await channel.pipeline.removeHandler(name: name)
        }
    }

    enum Err: String, ErrList {
        var domain: String { "woo.sys.client.err" }
        case requestFormatError = "请求格式有误"
        case requestBodyTooLarge = "请求的内容过大"
        case requestParseFailed = "服务器响应头解包时出错"
        case requestDomainParseFailed = "域名解析失败"
    }
}
