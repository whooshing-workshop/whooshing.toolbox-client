import Cryptos
import ErrorHandle
import NIOConcurrencyHelpers
import NIO
import Logging
import NIOHTTP1
import AsyncHTTPClient

/// 一个用于发起 API 子模块请求的客户端类，封装了鉴权和请求配置。
/// 并自动将用户凭据与令牌存储在请求上下文中，用于后续认证
///
/// 实现了数据流发送的 Backpressure 机制，因此尽管大数据流发送也不会产生内存堆积和泄漏的问题。
/// 该类型的所有接口见协议 `WhooshingClient`
///
/// - Warning: 该请求类型使用了 Whooshing 自定加密，因此无法访问任何常规 HTTP 或 HTTPS
/// 网站服务，仅应当用于访问 WHooshing 系统的 API 服务子模块。请勿使用 HTTPS 协议请求连线
/// ，使用 HTTP 即可。
public final class ApiClient: Sendable {
    
    public var key: Crypto.Symm.Key? {
        guard
            let ioData = client.storage[API.RequestIOData.self],
            let channel = client.channel,
            let key = ioData.connectionKeys[ObjectIdentifier(channel)]
        else { return nil }
        return key
    }
    
    /// 当前正在进行的请求所在的 TCP NIO Channel
    public weak var channel: (any Channel)? { client.channel }
    /// 日志系统
    public var logger: Logger? { client.logger }
    /// 主要的 EventLoop
    public var eventLoop: EventLoop { client.eventLoop }
    
    private let client: APIReqClient
    private let allocator = ByteBufferAllocator()
    
    /// 使用指定的事件循环和日志器初始化 API 客户端。
    ///
    ///
    /// - Parameters:
    ///   - credential: 用户凭据（Base64 编码的字符串）。
    ///   - token: 用户令牌（Base64 编码的字符串）。
    ///   - eventLoop: 所属的事件循环，用于异步操作。
    ///   - logger: 可选的日志记录器，默认值为 `nil`。
    public init(credential: String, token: String, eventLoop: EventLoop, logger: Logger? = nil) {
        self.client = .new(eventLoop: eventLoop, logger: logger, byteBufferAllocator: allocator)
        client.storage[API.RequestIOData.self] = .init(credential: credential, token: token)
    }
    
    public func removeHTTPHandlers(in eventLoop: any EventLoop) -> EventLoopFuture<Void> {
        self.client.removeHTTPHandlers(in: eventLoop)
    }
    
    public func removeHTTPHandlers() async throws {
        try await self.client.removeHTTPHandlers()
    }
    
    /// 关闭所有正在进行的连线
    public func closeAll() async {
        await client.closeAll()
    }

    deinit {
        client.logger?.debug("API.Client-主动关闭连接")
        Task { [weak client] in
            await client?.closeAll()
        }
    }
}

/// 实现 WhooshingClient 协议，以继承其默认实现
extension ApiClient: WhooshingClient {
    public func send(
        _ request: HTTPRequest
    ) -> EventLoopFuture<HTTPResponse> {
        client.send(request)
    }

    public var fileEventLoop: any EventLoop { client.fileEventLoop }
}
