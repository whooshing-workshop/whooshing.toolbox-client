import Cryptos
import ErrorHandle
import NIOConcurrencyHelpers
import NIO
import Logging
import NIOHTTP1

/// `ApiClient` 是一个用于发起 API 请求的客户端类，封装了鉴权和请求配置。
///
/// 并自动将用户凭据与令牌存储在请求上下文中，用于后续认证。
public final class ApiClient: Sendable {
    
    public var key: Crypto.Symm.Key? {
        guard
            let ioData = client.storage[API.RequestIOData.self],
            let channel = client.channel,
            let key = ioData.connectionKeys[ObjectIdentifier(channel)]
        else { return nil }
        return key
    }
    
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

extension ApiClient: WhooshingClient {
    public func send(
        _ method: HTTPMethod,
        headers: HTTPHeaders,
        to url: WebURI,
        bufferStrategy: BufferStrategy,
        beforeSend: @escaping @Sendable (inout HTTPRequest, Channel) throws -> (),
        afterSend: @escaping @Sendable (Channel) -> EventLoopFuture<Void>,
        progress: @escaping @Sendable (ProgressContext<HTTPResponse?>) throws -> Void = { _ in }
    ) -> EventLoopFuture<HTTPResponse?> {
        client.send(method, headers: headers, to: url, bufferStrategy: bufferStrategy, beforeSend: beforeSend, afterSend: afterSend, progress: progress)
    }

    public var fileEventLoop: any EventLoop { client.fileEventLoop }
}
