import NIOCore
import AsyncAlgorithms
import NIOHTTP1
import AsyncHTTPClient
import Logging
import ErrorHandle
import Foundation

public final class RequestWrapperHandler: ChannelDuplexHandler, RemovableChannelHandler, @unchecked Sendable {
    // 发出的是 HTTPClientRequest，拆成 HTTPClientRequestPart（写出）
    public typealias OutboundIn = HTTPRequest
    public typealias OutboundOut = HTTPClientRequestPart

    // 收到的是 HTTPClientResponsePart，组装为 HTTPClientResponse（读入）
    public typealias InboundIn = HTTPClientResponsePart
    public typealias InboundOut = HTTPResponse
    
    public let logger: Logger?
    
    public var promise: EventLoopPromise<InboundOut>? = nil
    
    private var currentStrategy: ResponseBufferStrategy? = nil
    private var currentResponse: HTTPResponse? = nil
    
    enum ReadingStatus: Sendable {
        case pause
        case resume
    }
    
    private enum ResponseBufferStrategy {
        case bytes(Int)
        case stream(
            SendTaskGroup,
            AsyncThrowingChannel<ByteBuffer, Error>
        )
    }
    
    public enum Err: String, ErrList {
        public var domain: String { "woo.sys.client.request.wrapper.handler" }
        case responseNotValid = "对方的响应不合法"
        case unknow = "未知错误"
    }
    
    init(logger: Logger?) {
        self.logger = logger
    }
    
    public func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        let part = unwrapInboundIn(data)
        guard let promise = promise else { fatalError("未指定 promise") }
        switch part {
        case .head(let head):
            var res = HTTPResponse(status: head.status, version: head.version, headers: head.headers)
            res.channel = context.channel
            // websocket
            guard head.status != .switchingProtocols else {
                promise.succeed(res)
                return
            }
            for h in head.headers {
                if h.name == "content-length" {
                    guard let bodySize = Int(h.value) else {
                        errorCaught(context: context, error: Err.responseNotValid.d("content-type 头大小解析失败", 15001))
                        return
                    }
                    self.currentStrategy = .bytes(bodySize)
                    self.currentResponse = res
                    return
                } else if h.name == "transfer-encoding" && h.value.lowercased() == "chunked" {
                    let stream = AsyncThrowingChannel<ByteBuffer, Error>()
                    res.body = .stream(stream)
                    let sendGroup = SendTaskGroup()
                    self.currentStrategy = .stream(sendGroup, stream)
                    promise.succeed(res)
                    return
                }
            }
            errorCaught(context: context, error: Err.responseNotValid.d("未找到 content-type 或 transfer-encoding 头", 15002))
        case .body(let body):
            guard let strategy = self.currentStrategy else { fatalError("机制错误，strategy 未指定") }
            
            switch strategy {
            case .bytes(let totalSize):
                guard let res = self.currentResponse else { fatalError("机制错误，此处应当已创建 Response 头") }
                guard totalSize > 0 else { self.currentResponse?.body = nil; return }
                if let resBody = res.body {
                    guard case var .bytes(buffer) = resBody.type else { fatalError("机制错误，此处的 Response body 应当为 byte") }
                    buffer.writeImmutableBuffer(body)
                    if buffer.readableBytes > totalSize {
                        errorCaught(context: context, error: Err.responseNotValid.d("预计大小为 \(ChunkTool.formatByteSize(totalSize))，总共收到 \(ChunkTool.formatByteSize(buffer.readableBytes))", 15003))
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
            
        case .end:
            guard let strategy = self.currentStrategy else { fatalError("机制错误，strategy 未指定") }
            switch strategy {
            case .bytes:
                guard let res = self.currentResponse else { fatalError("机制错误，此处应当已创建 Response 头") }
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
                            self.errorCaught(context: context, error: error)
                        }.get()
                    }
                }
            }
        } else {
            context.writeAndFlush(self.wrapOutboundOut(.end(nil)), promise: promise)
        }
    }
    
    public func errorCaught(context: ChannelHandlerContext, error: any Error) {
        promise?.fail(error)
        context.fireErrorCaught(error)
    }
}

actor SendTaskGroup {
    private var tasks: [Task<Void, Never>] = []

    func add(_ operation: @escaping @Sendable () async -> Void) {
        tasks.append(Task {
            await operation()
            self.tasks.removeFirst()
        })
    }

    func waitAll() async {
        for t in tasks {
            await t.value
        }
        tasks.removeAll()
    }
}
