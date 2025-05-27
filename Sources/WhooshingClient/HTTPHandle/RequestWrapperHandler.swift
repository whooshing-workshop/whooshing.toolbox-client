import NIOCore
import NIOHTTP1
import AsyncHTTPClient
import Logging
import ErrorHandle

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
    
    private enum ResponseBufferStrategy {
        case bytes(Int)
        case stream(AsyncThrowingStream<ByteBuffer, Error>.Continuation)
    }
    
    public enum Err: String, ErrList {
        public var domain: String { "woo.sys.client.request.wrapper.handler" }
        case responseNotValid = "对方的响应不合法"
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
            for h in head.headers {
                if h.name == "content-type" {
                    guard let bodySize = Int(h.value) else {
                        errorCaught(context: context, error: Err.responseNotValid.d("content-type 头大小解析失败", 15001))
                        return
                    }
                    self.currentStrategy = .bytes(bodySize)
                    self.currentResponse = res
                    return
                } else if h.name == "transfer-encoding" && h.value.lowercased() == "chunked" {
                    let (stream, writer) = AsyncThrowingStream<ByteBuffer, Error>.makeStream()
                    res.body = .stream(stream)
                    self.currentStrategy = .stream(writer)
                    promise.succeed(res)
                    return
                }
            }
            errorCaught(context: context, error: Err.responseNotValid.d("未找到 content-type 或 transfer-encoding 头", 15002))
        case .body(var body):
            guard let strategy = self.currentStrategy else { fatalError("机制错误，strategy 未指定") }
            
            switch strategy {
            case .bytes(let totalSize):
                guard var res = self.currentResponse else { fatalError("机制错误，此处应当已创建 Response 头") }
                guard totalSize > 0 else { res.body = nil; return }
                if let resBody = res.body {
                    guard case var .bytes(buffer) = resBody.type else { fatalError("机制错误，此处的 Response body 应当为 byte") }
                    buffer.writeBuffer(&body)
                    if buffer.readableBytes > totalSize {
                        errorCaught(context: context, error: Err.responseNotValid.d("预计大小为 \(ChunkTool.formatByteSize(totalSize))，总共收到 \(ChunkTool.formatByteSize(buffer.readableBytes))", 15003))
                    }
                    res.body = .bytes(buffer)
                } else {
                    res.body = .bytes(body)
                }
            case .stream(let writer):
                writer.yield(body)
            }
            
        case .end:
            guard let strategy = self.currentStrategy else { fatalError("机制错误，strategy 未指定") }
            switch strategy {
            case .bytes:
                guard let res = self.currentResponse else { fatalError("机制错误，此处应当已创建 Response 头") }
                promise.succeed(res)
            case .stream(let writer): writer.finish()
            }
        }
    }
    
    public func write(context: ChannelHandlerContext, data: NIOAny, promise: EventLoopPromise<Void>?) {
        let request = unwrapOutboundIn(data)
        let head = HTTPRequestHead(version: request.version, method: request.method, uri: request.url.string, headers: request.headers)
        context.write(wrapOutboundOut(.head(head)), promise: nil)
        if let body = request.body {
            switch body.type {
            case .bytes(let bytes):
                context.write(self.wrapOutboundOut(.body(.byteBuffer(bytes))), promise: nil)
                context.write(self.wrapOutboundOut(.end(nil)), promise: promise)
            case .stream(let stream):
                context.eventLoop.makeFutureWithTask {
                    var iterator = stream.makeAsyncIterator()
                    while let chunk = try await iterator.next() {
                        context.write(self.wrapOutboundOut(.body(.byteBuffer(chunk))), promise: nil)
                    }
                    context.write(self.wrapOutboundOut(.end(nil)), promise: nil)
                }.cascade(to: promise)
            }
        } else {
            context.write(self.wrapOutboundOut(.end(nil)), promise: promise)
        }
    }
    
    public func errorCaught(context: ChannelHandlerContext, error: any Error) {
        
    }
}
