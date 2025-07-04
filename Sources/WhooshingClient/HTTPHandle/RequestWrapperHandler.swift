import NIOCore
import AsyncAlgorithms
import NIOHTTP1
import AsyncHTTPClient
import Logging
import NIOAdvanced
import ErrorHandle
import Foundation

public final class RequestWrapperHandler: ChannelDuplexHandler, RemovableChannelHandler, @unchecked Sendable {
    // 发出的是 HTTPClientRequest，拆成 HTTPClientRequestPart（写出）
    public typealias OutboundIn = HTTPRequest
    public typealias OutboundOut = HTTPClientRequestPart

    // 收到的是 HTTPClientResponsePart，组装为 HTTPClientResponse（读入）
    public typealias InboundIn = HTTPClientResponsePart
    public typealias InboundOut = HTTPResponse
    
    @frozen
    public enum Errcase: String, ErrList {
        case responseNotValid = "对方的响应不合法"
        case cancelled = "外部错误，被取消"
        case internalFailure = "内部错误"
    }
    
    public let logger: Logger?
    
    public var promise: EventLoopTarget<InboundOut, Errcase.ErrType>? = nil
    
    @usableFromInline
    private(set) var currentStrategy: ResponseBufferStrategy? = nil
    @usableFromInline
    private(set) var currentResponse: HTTPResponse? = nil
    
    @usableFromInline
    enum ReadingStatus: Sendable {
        case pause
        case resume
    }
    
    @usableFromInline
    enum ResponseBufferStrategy {
        case bytes(Int)
        case stream(
            SendTaskGroup,
            AsyncThrowingChannel<ByteBuffer, Error>
        )
    }
    
    @inlinable
    init(logger: Logger?) {
        self.logger = logger
    }
    
    @inlinable
    public func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        guard let promise = promise else { fatalError("未指定 promise") }
        
        let part = unwrapInboundIn(data)
        do {
            let res: InboundOut?
            
            switch part {
            case .head(let head): res = try readHead(context: context, head: head)
            case .body(let body): try readBody(context: context, body: body); res = nil
            case .end: res = try readEnd(context: context)
            }
            
            if let r = res { promise.succeed(r) }
        } catch {
            promise.fail(error)
            context.fireErrorCaught(error)
        }
    }
    
    @inlinable
    public func write(context: ChannelHandlerContext, data: NIOAny, promise: EventLoopPromise<Void>?) {
        let request = unwrapOutboundIn(data)
        let head = HTTPRequestHead(version: request.version, method: request.method, uri: request.url.queryPath, headers: request.headers)
        context.write(wrapOutboundOut(.head(head)), promise: nil)
        context.triggerUserOutboundEvent(ReadingStatus.resume, promise: nil)
        if let body = request.body {
            switch body.type {
            case .bytes(let bytes):
                context.write(self.wrapOutboundOut(.body(.byteBuffer(bytes))), promise: nil)
                context.writeAndFlush(self.wrapOutboundOut(.end(nil)), promise: promise)
            case .stream(let stream):
                promise?.succeed()
                Task {
                    do {
                        for try await chunk in stream {
                            try await context.eventLoop.flatSubmit {
                                context.writeAndFlush(self.wrapOutboundOut(.body(.byteBuffer(chunk))))
                            }.get()
                        }
                        try await context.eventLoop.flatSubmit {
                            context.writeAndFlush(self.wrapOutboundOut(.end(nil)))
                        }.get()
                    } catch {
                        try? await context.eventLoop.submit {
                            promise?.fail(Errcase.internalFailure.subErr(error))
                            context.fireErrorCaught(error)
                        }.get()
                    }
                }
            }
        } else {
            context.writeAndFlush(self.wrapOutboundOut(.end(nil)), promise: promise)
        }
    }
}

extension RequestWrapperHandler {
    @inlinable
    func readHead(context: ChannelHandlerContext, head: HTTPResponseHead) throws(BscError<Errcase>) -> InboundOut? {
        var res = HTTPResponse(status: head.status, version: head.version, headers: head.headers)
        res.channel = context.channel
        // websocket
        guard head.status != .switchingProtocols else {
            return res
        }
        for h in head.headers {
            if h.name == "content-length" {
                guard let bodySize = Int(h.value) else {
                    throw Errcase.responseNotValid.d("content-type 头大小解析失败")
                }
                self.currentStrategy = .bytes(bodySize)
                self.currentResponse = res
                return nil
            } else if h.name == "transfer-encoding" && h.value.lowercased() == "chunked" {
                let stream = AsyncThrowingChannel<ByteBuffer, Error>()
                res.body = .stream(stream)
                let sendGroup = SendTaskGroup()
                self.currentStrategy = .stream(sendGroup, stream)
                return res
            }
        }
        throw Errcase.responseNotValid.d("未找到 content-type 或 transfer-encoding 头")
    }
    
    @inlinable
    func readBody(context: ChannelHandlerContext, body: ByteBuffer) throws(BscError<Errcase>) {
        guard let strategy = self.currentStrategy else {
            throw Errcase.internalFailure.d("机制错误，strategy 未指定")
        }
        
        switch strategy {
        case .bytes(let totalSize):
            guard let res = self.currentResponse else {
                throw Errcase.internalFailure.d("机制错误，此处应当已创建 Response 头")
            }
            
            guard totalSize > 0 else {
                self.currentResponse?.body = nil
                return
            }
            
            if let resBody = res.body {
                guard case var .bytes(buffer) = resBody.type else {
                    throw Errcase.internalFailure.d("机制错误，此处的 Response body 应当为 byte")
                }
                
                buffer.writeImmutableBuffer(body)
                
                if buffer.readableBytes > totalSize {
                    throw Errcase.responseNotValid.d("预计大小为 \(ChunkTool.formatByteSize(totalSize))，总共收到 \(ChunkTool.formatByteSize(buffer.readableBytes))")
                }
                
                self.currentResponse?.body = .bytes(buffer)
            } else {
                self.currentResponse?.body = .bytes(body)
            }
            
            context.triggerUserOutboundEvent(ReadingStatus.resume, promise: nil)
        case .stream(let sendGroup, let writer):
            
            context.triggerUserOutboundEvent(ReadingStatus.pause, promise: nil)
            
            Task {
                await sendGroup.add {
                    await writer.send(body)
                    try? await context.eventLoop.submit {
                        context.triggerUserOutboundEvent(ReadingStatus.resume, promise: nil)
                    }.get()
                }
            }
        }
    }
    
    @inlinable
    func readEnd(context: ChannelHandlerContext) throws(BscError<Errcase>) -> InboundOut? {
        guard let strategy = self.currentStrategy else {
            throw Errcase.internalFailure.d("机制错误，strategy 未指定")
        }
        
        switch strategy {
        case .bytes:
            guard let res = self.currentResponse else {
                throw Errcase.internalFailure.d("机制错误，此处应当已创建 Response 头")
            }
            return res
            
        case .stream(let sendGroup, let writer):
            context.triggerUserOutboundEvent(ReadingStatus.pause, promise: nil)
            Task {
                await sendGroup.waitAll()
                writer.finish()
            }
            return nil
        }
    }
}

@usableFromInline
actor SendTaskGroup {
    @usableFromInline
    private(set) var tasks: [Task<Void, Never>] = []

    @inlinable
    func add(_ operation: @escaping @Sendable () async -> Void) {
        tasks.append(Task {
            await operation()
            self.tasks.removeFirst()
        })
    }

    @inlinable
    func waitAll() async {
        for t in tasks {
            await t.value
        }
        tasks.removeAll()
    }
    
    @inlinable
    init() {}
}
