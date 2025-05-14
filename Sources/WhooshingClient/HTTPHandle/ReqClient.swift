import Cryptos
import ErrorHandle
import NIOConcurrencyHelpers
import NIO
import NIOExtras
import NIOPosix
import Logging
import Foundation

open class ReqClient: @unchecked Sendable {
    public let eventLoop: EventLoop
    public let fileEventLoop: EventLoop
    public let logger: Logger?
    public let byteBufferAllocator: ByteBufferAllocator
    public var ioHandler: RequestIOHandler?
    public let storage: SendableStorage = .init()
    public internal(set) var channelPool: SendableDictionary<String, Channel> = .init()
    public weak var mainHandler: RemovableChannelHandler?
    public weak var channel: Channel? {
        if let channel = __channel, channel.isActive { return channel }
        return nil
    }
    
    private weak var __channel: Channel?
    private let headerPool: SendableDictionary<ObjectIdentifier, HTTPResponse> = .init()
    private var lock: NIOLock = .init()
    
    public required init(eventLoop: EventLoop, logger: Logger? = nil, byteBufferAllocator: ByteBufferAllocator, ioHandler: RequestIOHandler? = nil) {
        self.eventLoop = eventLoop
        self.fileEventLoop = eventLoop.next()
        self.logger = logger
        self.byteBufferAllocator = byteBufferAllocator
        self.ioHandler = ioHandler
    }

    public func makeChannel(url: WebURI) -> EventLoopFuture<(Channel, RequestHandler, domain: String?)> {
        
        guard [.http, .https].contains(url.scheme) else {
            return eventLoop.makeFailedFuture(Err.requestFormatError.d("预期请求协议为 http 或 https，但得到 \(url.scheme)", 13052, (#file, #line)))
        }

        let port: Int
        let isDomainHost = url.isDomainHost()
        if isDomainHost {
            port = url.port ?? (url.scheme == .https ? 443 : 20002)
        } else {
            guard let p = url.port else {
                return eventLoop.makeFailedFuture(Err.requestFormatError.d("无法获取 Port", 10081, (#file, #line)))
            }
            port = p
        }

        let id = "\(url.host):\(port)"

        if let channel = self.channelPool[id], channel.isActive {
            return channel.pipeline.handler(type: RequestHandler.self).flatMap { handler in
                self.__channel = channel
                self.mainHandler = handler
                return channel.eventLoop.makeSucceededFuture((channel, handler, isDomainHost ? url.host : nil))
            }
        }

        let handler = RequestHandler(promise: nil, logger: logger, byteBufferAllocator: byteBufferAllocator, ioHandler: ioHandler)

        let bootstrap = ClientBootstrap(group: self.eventLoop)
            .channelInitializer { channel in
                channel.pipeline.addHandlers([
                    LengthFieldPrepender(lengthFieldLength: .eight, lengthFieldEndianness: .big),
                    ByteToMessageHandler(LengthFieldBasedFrameDecoder(lengthFieldLength: .eight, lengthFieldEndianness: .big)),
                    handler
                ])
            }
            .channelOption(.socketOption(.tcp_nodelay), value: 1)
            .channelOption(.socketOption(.so_reuseaddr), value: 1)
            .channelOption(.maxMessagesPerRead, value: 1)

        return bootstrap.connect(host: url.host, port: port).map { channel in
            self.channelPool[id] = channel
            self.__channel = channel
            self.mainHandler = handler
            return (channel, handler, isDomainHost ? url.host : nil)
        }
    }

    public func send(
        _ c: HTTPRequest,
        channel: Channel,
        handler: RequestHandler,
        bufferStrategy: BufferStrategy,
        progress: @escaping ProgressAction
    ) -> EventLoopFuture<HTTPResponse?> {
        let promise = channel.eventLoop.makePromise(of: HTTPResponse?.self)
        let id = ObjectIdentifier(channel)
        var client = c
        if case let .streaming(totalSize, _) = bufferStrategy {
            client.body = nil
            client.headers.replaceOrAdd(name: "content-length", value: String(totalSize))
        } else if let body = client.body {
            client.headers.replaceOrAdd(name: "content-length", value: String(body.readableBytes))
        }
        handler.promise = promise
        handler.bufferStrategy = bufferStrategy
        handler.progress = { prog in
            if prog.response {
                if self.headerPool[id] == nil {
                    print(String(buffer: prog.data))
                    self.headerPool[id] = try Guard( { try .init(data: prog.data) }, throw: Err.requestParseFailed.d(14010, #file, #line))
                }
                let header = self.headerPool[id]!
                try progress(prog.copy(value: header))
                return
            }
            try progress(prog.copy(value: nil))
            if prog.done { self.headerPool[id] = nil }
        }
        return channel.writeAndFlush(client).flatMapError { err in
            self.logger?.warning("\(err)")
            promise.fail(err)
            return channel.eventLoop.makeFailedFuture(err)
        }.flatMap {
            promise.futureResult
        }
    }
    
    public func send(_ request: HTTPRequest) -> EventLoopFuture<HTTPResponse> { fatalError("不应执行该方法") }

    public func closeAll() async {
        for (_, channel) in channelPool {
            try? await channel.close(mode: .all)
            print("连接关闭")
        }
        channelPool.removeAll()
    }

    enum Err: String, ErrList {
        var domain: String { "woo.sys.client.err" }
        case requestFormatError = "请求格式有误"
        case requestBodyTooLarge = "请求的内容过大"
        case requestParseFailed = "服务器响应头解包时出错"
        case requestDomainParseFailed = "域名解析失败"
    }
}
