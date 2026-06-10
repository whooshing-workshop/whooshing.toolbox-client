import NIOCore
import NIOHTTP1
import NIOConcurrencyHelpers
import AsyncAlgorithms
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
        case upstreamFailure = "上游处理器发生错误"
        case internalFailure = "内部错误"
    }
    
    public let logger: Logger?
    public var promise: EventLoopTarget<InboundOut, Errcase.ErrType>? = nil
    
    private(set) var currentStrategy: ResponseBufferStrategy? = nil
    private(set) var currentResponse: HTTPResponse? = nil
    
    enum ReadingStatus: String, Sendable, CustomStringConvertible {
        case pause
        case resume
        
        var description: String {
            self.rawValue
        }
    }
    
    enum ResponseBufferStrategy: CustomStringConvertible {
        case bytes(Int)
        case stream(
            SendTaskGroup,
            AsyncThrowingChannel<ByteBuffer, Error>
        )
        
        var description: String {
            switch self {
            case .bytes(let bytes): "bytes(\(bytes))"
            case .stream: "stream"
            }
        }
    }
    
    @inlinable
    init(logger: Logger?) {
        self.logger = logger
    }
    
    public func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        self.logger?.debug("Channel 读取数据", metadata: ["data": .string(data.description)])
        guard let promise = promise else { fatalError("未指定 promise") }
        
        let part = unwrapInboundIn(data)
        
        switch part {
        case .head(let head): readHead(context: context, head: head, promise: promise)
        case .body(let body): readBody(context: context, body: body, promise: promise)
        case .end: readEnd(context: context, promise: promise)
        }
    }
    
    public func write(context: ChannelHandlerContext, data: NIOAny, promise: EventLoopPromise<Void>?) {
        self.logger?.debug("Channel 写入数据", metadata: ["data": .string(data.description)])
        
        let request = unwrapOutboundIn(data)
        let head = HTTPRequestHead(version: request.version, method: request.method, uri: request.url.queryPath, headers: request.headers)
        self.logger?.debug("正在写入请求头", metadata: ["head": .stringConvertible(head)])
        context.write(wrapOutboundOut(.head(head)), promise: nil)
        context.triggerUserOutboundEvent(ReadingStatus.resume, promise: nil)
        let loopBound = context.loopBound
        if let body = request.body {
            switch body.type {
            case .bytes(let bytes):
                self.logger?.debug("正在写入固定请求体数据", metadata: ["body": .stringConvertible(bytes)])
                context.write(self.wrapOutboundOut(.body(.byteBuffer(bytes))), promise: nil)
                self.logger?.debug("正在写入固定请求体结尾")
                context.writeAndFlush(self.wrapOutboundOut(.end(nil)), promise: promise)
            case .stream(let stream):
                self.logger?.debug("准备流式写入请求体数据")
                promise?.succeed()
                Task {
                    do {
                        for try await chunk in stream {
                            try await loopBound.value.eventLoop.flatSubmit {
                                self.logger?.debug("请求流写入数据体", metadata: ["data": .stringConvertible(chunk)])
                                return loopBound.value.writeAndFlush(self.wrapOutboundOut(.body(.byteBuffer(chunk))))
                            }.get()
                        }
                        try await loopBound.value.eventLoop.flatSubmit {
                            self.logger?.debug("请求流写入结尾")
                            return loopBound.value.writeAndFlush(self.wrapOutboundOut(.end(nil)))
                        }.get()
                    } catch {
                        try? await loopBound.value.eventLoop.submit {
                            self.errorCaught(context: loopBound.value, error: Errcase.internalFailure.subErr(error))
                        }.get()
                    }
                }
            }
        } else {
            self.logger?.debug("请求体为空，仅写入请求体结尾")
            context.writeAndFlush(self.wrapOutboundOut(.end(nil)), promise: promise)
        }
    }
    
    public func errorCaught(context: ChannelHandlerContext, error: any Error) {
        logger?.warning("\(error)")
        if let err = error as? Errcase.ErrType {
            promise?.fail(err)
            context.fireErrorCaught(err)
        } else {
            let err = Errcase.upstreamFailure.subErr(error)
            promise?.fail(err)
            context.fireErrorCaught(err)
        }
    }
}

extension RequestWrapperHandler {
    func readHead(
        context: ChannelHandlerContext,
        head: HTTPResponseHead,
        promise: EventLoopTarget<InboundOut, Errcase.ErrType>
    ) {
        self.logger?.debug("读取到响应头", metadata: ["head": .stringConvertible(head)])
        var res = HTTPResponse(status: head.status, version: head.version, headers: head.headers)
        res.channel = context.channel
        // websocket
        guard head.status != .switchingProtocols else {
            self.logger?.info("升级至 WebSocket")
            promise.succeed(res)
            return
        }
        for h in head.headers {
            if h.name.lowercased() == "content-length" {
                self.logger?.debug("该响应为固定响应体的一次响应", metadata: ["content-length": .string(h.value)])
                guard let bodySize = Int(h.value) else {
                    self.errorCaught(context: context, error: Errcase.responseNotValid.d("content-type 头大小解析失败"))
                    return
                }
                self.currentStrategy = .bytes(bodySize)
                self.currentResponse = res
                return
            } else if h.name.lowercased() == "transfer-encoding" && h.value.lowercased() == "chunked" {
                self.logger?.debug("该响应为流式响应")
                let stream = AsyncThrowingChannel<ByteBuffer, Error>()
                res.body = .stream(stream)
                let sendGroup = SendTaskGroup()
                self.currentStrategy = .stream(sendGroup, stream)
                promise.succeed(res)
                return
            }
        }
        self.errorCaught(context: context, error: Errcase.responseNotValid.d("未找到 content-type 或 transfer-encoding 头"))
    }
    
    func readBody(
        context: ChannelHandlerContext,
        body: ByteBuffer,
        promise: EventLoopTarget<InboundOut, Errcase.ErrType>
    ) {
        self.logger?.debug("读取到响应体", metadata: ["body": .stringConvertible(body)])
        guard let strategy = self.currentStrategy else {
            promise.fail(Errcase.internalFailure.d("机制错误，strategy 未指定"))
            return
        }
        let loopBound = context.loopBound
        switch strategy {
        case .bytes(let totalSize):
            self.logger?.debug("固定响应体收集数据", metadata: ["total_size": .stringConvertible(totalSize)])
            
            guard let res = self.currentResponse else {
                self.errorCaught(context: context, error: Errcase.internalFailure.d("机制错误，此处应当已创建 Response 头"))
                return
            }
            
            guard totalSize > 0 else {
                self.logger?.info("响应体为空，未收集任何内容")
                self.currentResponse?.body = nil
                return
            }
            
            if let resBody = res.body {
                guard case var .bytes(buffer) = resBody.type else {
                    self.errorCaught(context: context, error: Errcase.internalFailure.d("机制错误，此处的 Response body 应当为 byte"))
                    return
                }
                
                buffer.writeImmutableBuffer(body)
                
                if buffer.readableBytes > totalSize {
                    self.errorCaught(context: context, error: Errcase.responseNotValid.d("实际收集到的数据大小与预期不符").metadata([
                        "expect_size": .string(ChunkTool.formatByteSize(totalSize)),
                        "actual_size": .string(ChunkTool.formatByteSize(buffer.readableBytes))
                    ]))
                }
                
                self.logger?.debug("收集到数据", metadata: ["data": .stringConvertible(buffer)])
                
                self.currentResponse?.body = .bytes(buffer)
            } else {
                self.logger?.debug("收集到数据", metadata: ["data": .stringConvertible(body)])
                
                self.currentResponse?.body = .bytes(body)
            }
            
            context.triggerUserOutboundEvent(ReadingStatus.resume, promise: nil)
        case .stream(let sendGroup, let writer):
            self.logger?.debug("流式响应体收集数据")
            context.triggerUserOutboundEvent(ReadingStatus.pause, promise: nil)
            sendGroup.add {
                await writer.send(body)
                self.logger?.debug("收集到数据-流式", metadata: ["data": .stringConvertible(body)])
                try? await loopBound.value.eventLoop.submit {
                    loopBound.value.triggerUserOutboundEvent(ReadingStatus.resume, promise: nil)
                }.get()
            }
        }
    }
    
    func readEnd(
        context: ChannelHandlerContext,
        promise: EventLoopTarget<InboundOut, Errcase.ErrType>
    ) {
        self.logger?.debug("读取到响应结尾")
        guard let strategy = self.currentStrategy else {
            self.errorCaught(context: context, error: Errcase.internalFailure.d("机制错误，strategy 未指定"))
            return
        }
        
        switch strategy {
        case .bytes:
            guard let res = self.currentResponse else {
                self.errorCaught(context: context, error: Errcase.internalFailure.d("机制错误，此处应当已创建 Response 头"))
                return
            }
            promise.succeed(res)
        case .stream(let sendGroup, let writer):
            context.triggerUserOutboundEvent(ReadingStatus.pause, promise: nil)
            Task {
                await sendGroup.waitAll()
                writer.finish()
            }
        }
    }
}

@usableFromInline
final class SendTaskGroup: @unchecked Sendable {
    
    @usableFromInline
    let lock = NIOLock()
    
    @inlinable
    var tasks: [Task<Void, Never>] {
        get {
            lock.withLock {
                __tasks
            }
        }
        set {
            lock.withLock {
                __tasks = newValue
            }
        }
    }
    
    @usableFromInline
    private(set) var __tasks: [Task<Void, Never>] = []
    
    @inlinable
    func add(_ operation: @escaping @Sendable () async -> Void) {
        tasks.append(Task {
            await operation()
        })
    }

    @inlinable
    func waitAll() async {
        for t in tasks {
            await t.value
        }
        tasks.removeAll()
    }
}
