import Cryptos
import AsyncAlgorithms
import ErrorHandle
import NIOConcurrencyHelpers
import NIO
import NIOAdvanced
import Logging
import NIOHTTP1
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
    public var key: Cryptos.Crypto.Symm.Key? { fatalError("永远不应调用此属性") }
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
    @Sendable
    public func send(
        _ request: HTTPRequest
    ) -> EventLoopResult<HTTPResponse, Failure> {
        fileEventLoop.makeFutureWithTask { () throws(Failure) in
            try await self.streamingSend(request)
        }.withError()
    }

    /// 析构函数，在实例释放时关闭内部 HTTPClient。
    @inlinable
    deinit {
        try? self.client.syncShutdown()
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
        
        _ = try await required(throws: Errcase.urlConnectionFailed, request.url.string) {
            try await Curl.isUriConnectable(request.url.string).get()
        }
        
        if let body = request.body {
            switch body.type {
            case .bytes(let bytes): req.body = .bytes(bytes)
            case .stream(let stream): req.body = .stream(stream, length: .unknown)
            }
        }
        self.logger?.info("HTTPS.Client-发送请求: \(request.url)")
        let response = try await required(throws: Errcase.requestSendFailed, request.url.string) {
            try await client.execute(req, deadline: .distantFuture, logger: logger)
        }
        
        var res = HTTPResponse(status: response.status, version: response.version, headers: response.headers)
        
        for h in response.headers {
            if h.name == "content-length" {
                guard let bodySize = Int(h.value) else {
                    throw Errcase.responseParseFailed.d("content-type 头大小解析失败")
                }
                
                res.body = try await required(throws: Errcase.streamingEngageFailed) {
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
                        let err = Errcase.streamingEngageFailed.subErr(error)
                        stream.fail(err)
                    }
                }
                res.body = .stream(stream)
                return res
            }
        }
        throw Errcase.responseNotValid.d("未找到 content-type 或 transfer-encoding 头")
    }
}
