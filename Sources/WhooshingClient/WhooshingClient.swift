import Cryptos
import NIOCore
import NIOHTTP1
import NIOAdvanced
import ErrorHandle

/// `WhooshingClient` 是一个通用的 HTTP 客户端协议，
/// 定义了发送各种 HTTP 请求的方法，包括 GET、POST、PUT、PATCH、DELETE 和自定义方法。
///
/// 实现该协议的类型可用于构造和发送 HTTP 请求，并返回异步响应（`EventLoopFuture<HTTPResponse>`）。
/// 通常与 `HTTPBody`、`WebURI` 和 `HTTPRequest` 等类型配合使用。
///
/// ---------
///
/// 首先，得到一个任何实现了 `WhooshingClient` 协议的类型，Whooshing 系统中
/// 分别对应 Api, Https, Inline 模块的请求类型有：
/// - `ApiClient`
/// - `HttpsClient`
/// - `InlineReqClient` (仅可在服务器中作为服务模块间通讯时使用)
///
/// ```swift
/// let client: WhooshingClient = ...
/// ```
///
/// 创建一个 URI 并准备好请求的数据体
///
/// ```swift
/// let uri = WebURI(path: "/upload")
/// let body = try HTTPBody.text("Hello, server!")
/// ```
///
/// 将数据以 post 方式发送，你可以得到结果
/// - .success: 获得服务器的响应，为 `HTTPResponse`
/// - .failure: 获得详细的错误
///
/// ```swift
/// client.post(uri, body: body).whenComplete { result in
///     switch result {
///     case .success(let response):
///         print("状态码: \(response.status)")
///     case .failure(let error):
///         print("请求失败: \(error)")
///     }
/// }
/// ```
///
/// ### 请求类型选择：
///
/// - `get(...)`：用于无副作用地获取资源
/// - `post(...)`：提交数据（如表单、JSON）
/// - `put(...)`：完整替换资源
/// - `patch(...)`：局部更新资源
/// - `delete(...)`：删除指定资源
/// - `send(...)`：完全自定义请求（方法 + 头 + 体）
///
/// 该协议也支持通过 `HTTPRequest` 类型直接发送构造好的请求对象。
///
public protocol WhooshingClient: AnyObject,Sendable {
    
    associatedtype Errcase: ErrList
    typealias Failure = Errcase.ErrType
    
    /// 用于文件操作的EventLoop
    var fileEventLoop: EventLoop { get }
    var key: Crypto.Symm.Key? { get }
    var channel: (any Channel)? { get }
    func removeHTTPHandlers() async -> Result<Void, Failure>
    func removeHTTPHandlers(in eventLoop: any EventLoop) -> EventLoopResult<Void, Failure>
    
    // MARK: - 核心实现
    
    /// 发送一个 GET 请求。
    ///
    /// - Parameters:
    ///   - url: 请求的目标 URL。
    ///   - body: 可选的请求体。
    ///   - headers: HTTP 请求头。
    /// - Returns: 表示响应的 `EventLoopFuture<HTTPResponse>`。
    func get(_ url: WebURI, body: HTTPBody?, headers: HTTPHeaders) -> EventLoopResult<HTTPResponse, Failure>
    
    /// 发送一个 POST 请求。
    ///
    /// - Parameters:
    ///   - url: 请求的目标 URL。
    ///   - body: 可选的请求体。
    ///   - headers: HTTP 请求头。
    /// - Returns: 表示响应的 `EventLoopFuture<HTTPResponse>`。
    func post(_ url: WebURI, body: HTTPBody?, headers: HTTPHeaders) -> EventLoopResult<HTTPResponse, Failure>
    
    /// 发送一个 PATCH 请求。
    ///
    /// - Parameters:
    ///   - url: 请求的目标 URL。
    ///   - body: 可选的请求体。
    ///   - headers: HTTP 请求头。
    /// - Returns: 表示响应的 `EventLoopFuture<HTTPResponse>`。
    func patch(_ url: WebURI, body: HTTPBody?, headers: HTTPHeaders) -> EventLoopResult<HTTPResponse, Failure>
    
    /// 发送一个 PUT 请求。
    ///
    /// - Parameters:
    ///   - url: 请求的目标 URL。
    ///   - body: 可选的请求体。
    ///   - headers: HTTP 请求头。
    /// - Returns: 表示响应的 `EventLoopFuture<HTTPResponse>`。
    func put(_ url: WebURI, body: HTTPBody?, headers: HTTPHeaders) -> EventLoopResult<HTTPResponse, Failure>
    
    /// 发送一个 DELETE 请求。
    ///
    /// - Parameters:
    ///   - url: 请求的目标 URL。
    ///   - body: 可选的请求体。
    ///   - headers: HTTP 请求头。
    /// - Returns: 表示响应的 `EventLoopFuture<HTTPResponse>`。
    func delete(_ url: WebURI, body: HTTPBody?, headers: HTTPHeaders) -> EventLoopResult<HTTPResponse, Failure>
    
    /// 发送一个自定义方法的 HTTP 请求。
    ///
    /// - Parameters:
    ///   - method: 请求方法（如 GET、POST 等）。
    ///   - url: 请求的目标 URL。
    ///   - body: 可选的请求体。
    ///   - headers: HTTP 请求头。
    /// - Returns: 表示响应的 `EventLoopFuture<HTTPResponse>`。
    func send(_ method: HTTPMethod, to url: WebURI, body: HTTPBody?, headers: HTTPHeaders) -> EventLoopResult<HTTPResponse, Failure>

    /// 发送一个自定义 `HTTPRequest`。
    ///
    /// - Parameter request: 要发送的请求对象。
    /// - Returns: 表示响应的 `EventLoopFuture<HTTPResponse>`。
    func send(_ request: HTTPRequest) -> EventLoopResult<HTTPResponse, Failure>
}

public extension WhooshingClient {
    @inlinable
    func get(
        _ url: WebURI,
        body: HTTPBody? = nil,
        headers: HTTPHeaders = [:]
    ) -> EventLoopResult<HTTPResponse, Failure> {
        send(.GET, to: url, body: body, headers: headers)
    }
    
    @inlinable
    func post(
        _ url: WebURI,
        body: HTTPBody? = nil,
        headers: HTTPHeaders = [:]
    ) -> EventLoopResult<HTTPResponse, Failure> {
        send(.POST, to: url, body: body, headers: headers)
    }
    
    @inlinable
    func patch(
        _ url: WebURI,
        body: HTTPBody? = nil,
        headers: HTTPHeaders = [:]
    ) -> EventLoopResult<HTTPResponse, Failure> {
        send(.PATCH, to: url, body: body, headers: headers)
    }
    
    @inlinable
    func put(
        _ url: WebURI,
        body: HTTPBody? = nil,
        headers: HTTPHeaders = [:]
    ) -> EventLoopResult<HTTPResponse, Failure> {
        send(.PUT, to: url, body: body, headers: headers)
    }
    
    @inlinable
    func delete(
        _ url: WebURI,
        body: HTTPBody? = nil,
        headers: HTTPHeaders = [:]
    ) -> EventLoopResult<HTTPResponse, Failure> {
        send(.DELETE, to: url, body: body, headers: headers)
    }
    
    @inlinable
    func send(
        _ method: HTTPMethod,
        to url: WebURI,
        body: HTTPBody? = nil,
        headers: HTTPHeaders = [:]
    ) -> EventLoopResult<HTTPResponse, Failure> {
        let request = HTTPRequest(method: method, url: url, headers: headers, body: body)
        return send(request)
    }
}

public final class AnyWhooshingClient<Errcase>: WhooshingClient, Sendable where Errcase: ErrList {
    @inlinable public var fileEventLoop: any EventLoop { getFileEventLoop() }
    @inlinable public var key: Cryptos.Crypto.Symm.Key? { getKey() }
    @inlinable public var channel: (any Channel)? { getChannel() }
    
    @usableFromInline let getFileEventLoop: @Sendable () -> any EventLoop
    @usableFromInline let getKey: @Sendable () -> Cryptos.Crypto.Symm.Key?
    @usableFromInline let getChannel: @Sendable () -> (any Channel)?
    @usableFromInline let removeHTTPHandlers: @Sendable () async -> Result<Void, Failure>
    @usableFromInline let removeHTTPHandlers2: @Sendable (any EventLoop) -> EventLoopResult<Void, Failure>
    @usableFromInline let send: @Sendable (_ request: HTTPRequest) -> EventLoopResult<HTTPResponse, Failure>
    
    @inlinable
    public init<T>(_ wrapped: T) where T: WhooshingClient, T.Errcase == Errcase {
        self.getFileEventLoop = { [wrapped] in wrapped.fileEventLoop }
        self.getKey = { [wrapped] in wrapped.key }
        self.getChannel = { [wrapped] in wrapped.channel }
        self.removeHTTPHandlers = { [wrapped] in await wrapped.removeHTTPHandlers() }
        self.removeHTTPHandlers2 = { [wrapped] in wrapped.removeHTTPHandlers(in: $0) }
        self.send = { [wrapped] in wrapped.send($0) }
    }
    
    @inlinable
    public func removeHTTPHandlers() async -> Result<Void, Failure> {
        await removeHTTPHandlers()
    }
    
    @inlinable
    public func removeHTTPHandlers(in eventLoop: any EventLoop) -> EventLoopResult<Void, Failure> {
        removeHTTPHandlers2(eventLoop)
    }
    
    @inlinable
    public func send(_ request: HTTPRequest) -> EventLoopResult<HTTPResponse, Failure> {
        send(request)
    }
}
