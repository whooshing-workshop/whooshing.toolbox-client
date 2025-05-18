import Cryptos
import ErrorHandle
import NIOConcurrencyHelpers
import NIO
import Logging
import NIOHTTP1
import AsyncHTTPClient
import Foundation

#if WHOOSHING_VAPOR
import Vapor
#endif

public final class HttpsClient: WhooshingClient, @unchecked Sendable {
    public enum Err: String, ErrList {
        public var domain: String { "woo.sys.httpsclient.err" }
        case streamingEngageFailed = "流传输数据获取失败"
        case responseHasNoContentLength = "所返回的响应没有提供 Content-Length"
        case urlConnectionFailed = "对该 url 目标地址连接失败"
    }
    
    public var key: Cryptos.Crypto.Symm.Key? { fatalError("永远不应调用此属性") }
    public var channel: (any NIOCore.Channel)? { fatalError("永远不应调用此属性") }
    public var mainHandler: (any NIOCore.RemovableChannelHandler & Sendable)? { fatalError("永远不应调用此属性") }
    public var fileEventLoop: any NIOCore.EventLoop
    public let logger: Logger?
    private let client: HTTPClient
    
    public init(in eventLoop: EventLoop, configuration: HTTPClient.Configuration = .singletonConfiguration, logger: Logger? = nil) {
        self.fileEventLoop = eventLoop
        self.logger = logger
        self.client = HTTPClient(eventLoopGroup: eventLoop, configuration: configuration)
    }
    
    public func send(
        _ method: HTTPMethod,
        headers: HTTPHeaders,
        to url: WebURI,
        bufferStrategy: BufferStrategy,
        beforeSend: @escaping BeforeSendAction,
        afterSend: @escaping AsyncAfterSendAction = defaultAfterSend,
        progress: @escaping ProgressAction
    ) -> EventLoopFuture<HTTPResponse> {
        fileEventLoop.submit {
            var req = HTTPRequest(method: method, url: url, headers: headers, body: nil)
            try beforeSend(&req, nil)
            return req
        }.flatMap { (req: HTTPRequest) in
            self.fileEventLoop.makeFutureWithTask {
                let res: HTTPClientResponse
                if case let .streaming(totalSize, stream) = bufferStrategy {
                    res = try await self.streamingSend(req: req, totalSize: totalSize, eventLoop: self.fileEventLoop, progress: progress, streaming: stream)
                } else {
                    res = try await self.streamingSend(req: req, totalSize: req.body?.readableBytes ?? 0, eventLoop: self.fileEventLoop, progress: progress) { request, eventLoop, maxChunk, currentIndex in
                        guard var body = req.body else { fatalError("body 为 nil，不应执行至此") }
                        guard let chunk = body.readSlice(length: maxChunk) else { fatalError("请求体大小错误，不应执行至此") }
                        return eventLoop.makeSucceededFuture(chunk)
                    }
                }
                return try await self.streamingParseResponse(response: res, progress: progress)
            }
        }
    }
    
    deinit {
        try? self.client.syncShutdown()
    }
}

extension HttpsClient {
    private func streamingSend(
        req: HTTPRequest,
        totalSize: Int,
        eventLoop: EventLoop,
        progress: @escaping ProgressAction,
        streaming: @escaping AsyncStreamingDataAction
    ) async throws -> HTTPClientResponse {
        let stream = AsyncThrowingStream<ByteBuffer, Error> { continuation in
            Task {
                var curSize = 0
                var i = 0
                do {
                    // 发送请求头
                    let (head, _) = try req.data()
                    self.logger?.trace("HTTPS.Write-正在向服务器流传输 流数据头，数据体总大小: \(totalSize)")
                    var prog = ProgressContext<HTTPResponse?>(index: -1, data: head, done: totalSize == 0, curBytes: 0, totalBytes: totalSize, startDate: Date(), channel: nil, response: nil)
                    try progress(prog)
                    
                    // 发送请求体
                    while curSize < totalSize {
                        let nextChunkSize = min(ChunkTool.maxChunk, totalSize - curSize)
                        let data = try await streaming(req, eventLoop, nextChunkSize, i).get()
                        guard data.readableBytes <= nextChunkSize else {
                            throw Err.streamingEngageFailed.d("数据大小不正确，预期大小为 \(ChunkTool.formatByteSize(nextChunkSize)), 却得到了 \(ChunkTool.formatByteSize(data.readableBytes))", 15030)
                        }
                        
                        let yieldRes = continuation.yield(data)
                        guard case .enqueued(remaining:) = yieldRes else {
                            throw Err.streamingEngageFailed.d("未成功将数据添加到流中", 15030)
                        }
                        
                        curSize += data.readableBytes
                        prog = prog.next(data, done: curSize == totalSize)
                        self.logger?.trace("HTTPS.Write-正在向服务器流传输 块数据: 当前大小: \(prog.curBytesStr), 总大小: \(prog.totalBytesStr)")
                        try progress(prog)
                        i += 1
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
        
        var request = HTTPClientRequest(url: req.url.string)
        request.method = req.method
        request.headers = req.headers
        request.body = .stream(stream, length: .known(Int64(totalSize)))
        try await Curl.isUriConnectable(request.url)
        
        self.logger?.info("HTTPS.Client-发送请求: \(request.url)")
        return try await client.execute(request, deadline: .distantFuture, logger: logger)
    }
    
    private func streamingParseResponse(response: HTTPClientResponse, progress: @escaping ProgressAction) async throws -> HTTPResponse {
        let totalSize = response.headers.first(name: "content-length").flatMap(Int.init)
        
        var res = response.httpResponse
        
        var prog = ProgressContext<HTTPResponse?>(
            index: -1,
            data: response.headData(),
            done: totalSize == 0,
            curBytes: 0,
            totalBytes: totalSize,
            startDate: Date(),
            channel: nil,
            response: res
        )
        
        self.logger?.trace("HTTPS.Read-正在从服务器流接收 流数据头: 数据体总大小: \(totalSize ?? -1)")
        try progress(prog)

        if let size = totalSize {
            let data = try await response.body.collect(upTo: size)
            res.body = data
            self.logger?.trace("ReqIOHandler.Read-正在从服务器流 Collect 块数据: 总大小: \(prog.totalBytes ?? -1)")
            try progress(prog.next(data, done: true))
        } else {
            var curSize = 0
            for try await buffer in response.body {
                curSize += buffer.readableBytes
                prog = prog.next(buffer, done: false)
                self.logger?.trace("ReqIOHandler.Read-正在从服务器流接收 流数据: 当前大小: \(prog.curBytes), 总大小: \(prog.totalBytes ?? -1)")
                try progress(prog)
            }
            try progress(prog.next(.init(), done: true))
        }
        return res
    }
}


extension HTTPClientResponse {
    func headData(bufferAllocator: ByteBufferAllocator = .init()) -> ByteBuffer {
        var buffer = bufferAllocator.buffer(capacity: 0)
        let responseLine = "HTTP/\(version.major).\(version.minor) \(self.status.code) \(self.status.reasonPhrase)\r\n"
        buffer.writeString(responseLine)
        headers.forEach { (name, value) in buffer.writeString("\(name): \(value)\r\n") }
        buffer.writeString("\r\n")
        return buffer
    }
    
    var httpResponse: HTTPResponse {
        .init(status: status, body: nil, version: version, headers: headers)
    }
}
