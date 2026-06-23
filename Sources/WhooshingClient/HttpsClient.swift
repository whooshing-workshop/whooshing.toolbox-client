import NIO
import NIOAdvanced
import NIOHTTP1
import Cryptos
import LoggingAdvanced
import AsyncAlgorithms
import AsyncHTTPClient
import Foundation

/// `HttpsClient` 是一个基于 AsyncHTTPClient 封装的异步 HTTPS 请求客户端，
/// 提供统一的发送逻辑和错误封装，适用于文件传输等高性能场景。
///
/// 该类型的所有接口见协议 `WhooshingClient`
///
/// - Warning: 该 HttpsClient 并无任何 Whooshing 自定义加密，使用常规的 HTTPS 加密方式，因此无法
/// 访问任何 Whooshing 的 API 或 INLINE 子模块的任何服务，仅当用于访问常规的网站服务时使用，且避免使
/// HTTP 请求(明文)
///
/// - Warning: 该类型并没有配置 Backpressure 机制，因此不适合发送大型数据流，谨慎使用
public final class HttpsClient: WhooshingClient, @unchecked Sendable {
    public var key: SendableSymmKey? { fatalError("永远不应调用此属性") }
    public var channel: (any NIOCore.Channel)? { fatalError("永远不应调用此属性") }
    public var fileEventLoop: any NIOCore.EventLoop
    public let logger: Logger?
    @usableFromInline
    let client: HTTPClient

    /// 初始化一个 `HttpsClient` 实例。
    ///
    /// - Parameters:
    ///   - eventLoop: 用于驱动请求执行的 `EventLoop`。
    ///   - configuration: HTTPClient 的配置，默认为单例配置。
    ///   - logger: 可选的日志记录器，用于记录请求信息。
    @inlinable
    public init(in eventLoop: EventLoop, configuration: HTTPClient.Configuration = .singletonConfiguration, logger: Logger? = nil) {
        self.fileEventLoop = eventLoop
        self.logger = logger
        self.client = HTTPClient(eventLoopGroup: eventLoop, configuration: configuration)
    }

    /// 发送一个 `HTTPRequest` 请求，并返回异步的 `HTTPResponse`。
    ///
    /// - Parameter request: 要发送的请求对象。
    /// - Returns: 一个 `EventLoopResult`，其结果为 `HTTPResponse`。
    /// - Throws: 若响应不合法或连接失败，抛出 `HttpsClient.Errcase` 中定义的错误。
    @inlinable
    public func send(
        _ request: HTTPRequest
    ) -> EventLoopResult<HTTPResponse, Failure> {
        self.logger?.info("HTTPS.Client-发送请求", metadata: ["url": .data(request.url)])
        self.logger?.debug("请求内容", metadata: ["request": .data(request)])
        return fileEventLoop.bridge { () throws(Failure) in
            try await self.streamingSend(request)
        }
        .withError()
        .map { res in
            self.logger?.info("发送请求成功，收到响应", metadata: ["status": .stringConvertible(res.status)])
            self.logger?.debug("响应内容", metadata: ["response": .data(res)])
            return res
        }
        .logIfFailAndExist(logger: self.logger)
    }

    /// 关闭所有正在进行的连线
    @inlinable
    public func shutdown() async throws {
        logger?.info("HTTPS.Client-主动关闭连接")
        try await self.client.shutdown()
    }
    
    /// 关闭所有正在进行的连线
    @inlinable
    public func syncShutdown() throws {
        logger?.info("HTTPS.Client-主动关闭连接")
        try self.client.syncShutdown()
    }
    
    /// 析构函数，安全、非阻塞地在后台关闭内部 HTTPClient
    @inlinable
    deinit {
        // 局部捕获 client 指针，防止闭包循环引用 self
        let clientToShutdown = self.client
        let logger = self.logger
        
        logger?.info("HTTPS.Client-实例释放，开始派发后台异步关闭任务")
        
        // 使用 Task.detached 强行脱离当前的 EventLoop 线程
        Task.detached {
            do {
                // 在不阻塞网络线程的情况下，优雅地异步停机
                try await clientToShutdown.shutdown()
                logger?.info("HTTPS.Client-内部 HTTPClient 异步释放成功")
            } catch {
                logger?.error("HTTPS.Client-内部 HTTPClient 异步释放失败: \(error)")
            }
        }
    }

    /// 清除当前上下文中的 HTTP handler（该方法目前为兼容协议所需，实际为空实现）。
    ///
    /// - Parameter eventLoop: 所属的 `EventLoop`。
    /// - Returns: 一个立即完成的 `EventLoopResult<Void>`。
    ///
    /// - Warning: 你永远不应当调用该方法
    @inlinable
    public func removeHTTPHandlers(in eventLoop: any EventLoop) -> EventLoopResult<Void, Failure> {
        eventLoop.makeSucceededVoidResult()
    }

    /// 清除当前上下文中的 HTTP handler（异步接口，实际为空实现）。
    ///
    /// - Warning: 你永远不应当调用该方法
    @inlinable
    public func removeHTTPHandlers() async -> Res<Void, Errcase> { return .success(()) }
}

extension HttpsClient {
    @usableFromInline
    func streamingSend(
        _ request: HTTPRequest
    ) async throws(Failure) -> HTTPResponse {
        var req = HTTPClientRequest(url: request.url.string)
        req.method = request.method
        req.headers = request.headers
        
        _ = try await required(throws: Errcase.urlConnectionFailed, "URL 地址不可达", metadata: ["url": .data(request.url)], category: .external(suggestions: ["请检查URL以及网络连接或联系系统管理员以解决问题"])) {
            try await Curl.isUriConnectable(request.url.string).get()
        }
        
        if let body = request.body {
            switch body.type {
            case .bytes(let bytes): req.body = .bytes(bytes)
            case .stream(let stream): req.body = .stream(stream, length: .unknown)
            }
        }
        let response = try await required(throws: Errcase.requestSendFailed, request.url.string, category: .inherit) {
            try await client.execute(req, deadline: .distantFuture, logger: logger)
        }
        
        var res = HTTPResponse(status: response.status, version: response.version, headers: response.headers)
        
        for h in response.headers {
            if h.name == "content-length" {
                guard let bodySize = Int(h.value) else {
                    throw Errcase.responseParseFailed.d("content-type 头大小解析失败", category: .internal)
                }
                
                res.body = try await required(throws: Errcase.streamingEngageFailed, category: .internal) {
                    try await .bytes(response.body.collect(upTo: bodySize))
                }
                return res
            } else if h.name == "transfer-encoding" && h.value.lowercased() == "chunked" {
                let stream = AsyncThrowingChannel<ByteBuffer, Error>()
                // 异步收集流数据
                Task {
                    do {
                        for try await chunk in response.body {
                            await stream.send(chunk)
                        }
                        stream.finish()
                    } catch {
                        let err = Errcase.streamingEngageFailed.subErr(error, category: .inherit)
                        stream.fail(err)
                    }
                }
                res.body = .stream(stream)
                return res
            }
        }
        throw Errcase.responseNotValid.d("未找到 content-type 或 transfer-encoding 头", category: .internal)
    }
}
