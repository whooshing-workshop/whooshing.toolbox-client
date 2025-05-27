import Cryptos
import NIOCore
import NIOHTTP1

#if WHOOSHING_VAPOR
import Vapor
#endif

/// 定义异步在发送请求后执行的操作闭包
/// - Parameter channel: 用于发送请求的通道
/// - Returns: 返回一个EventLoopFuture，表示异步操作的结果
public typealias AfterSendAction =  @Sendable (_ channel: Channel) -> EventLoopFuture<Void>

/// 客户端协议，定义了与服务器交互的各种方法
public protocol WhooshingClient: AnyObject,Sendable {
    
    /// 用于文件操作的EventLoop
    var fileEventLoop: EventLoop { get }
    var key: Crypto.Symm.Key? { get }
    var channel: (any Channel)? { get }
    func removeHTTPHandlers(in eventLoop: any EventLoop) -> EventLoopFuture<Void>
    
    // MARK: - 核心实现
    func get(_ url: WebURI, body: HTTPBody?, headers: HTTPHeaders, afterSend: @escaping AfterSendAction) -> EventLoopFuture<HTTPResponse>
    func post(_ url: WebURI, body: HTTPBody?, headers: HTTPHeaders, afterSend: @escaping AfterSendAction) -> EventLoopFuture<HTTPResponse>
    func patch(_ url: WebURI, body: HTTPBody?, headers: HTTPHeaders, afterSend: @escaping AfterSendAction) -> EventLoopFuture<HTTPResponse>
    func put(_ url: WebURI, body: HTTPBody?, headers: HTTPHeaders, afterSend: @escaping AfterSendAction) -> EventLoopFuture<HTTPResponse>
    func delete(_ url: WebURI, body: HTTPBody?, headers: HTTPHeaders, afterSend: @escaping AfterSendAction) -> EventLoopFuture<HTTPResponse>
    func send(_ method: HTTPMethod, to url: WebURI, body: HTTPBody?, headers: HTTPHeaders, afterSend: @escaping AfterSendAction) -> EventLoopFuture<HTTPResponse>
    
    /// 默认的发送后操作实现
    static func defaultAfterSend(channel: Channel) -> EventLoopFuture<Void>

    /// 核心发送方法
    func send(
        _ request: HTTPRequest,
        afterSend: @escaping AfterSendAction
    ) -> EventLoopFuture<HTTPResponse>
}

public extension WhooshingClient {
    /// 默认的发送后操作实现
    /// - Parameter channel: 请求通道对象
    /// - Returns: 返回成功的EventLoopFuture
    /// - 说明: 提供空的默认实现，仅返回channel的已成功Future
    static func defaultAfterSend(channel: Channel) -> EventLoopFuture<Void> {
        channel.eventLoop.makeSucceededFuture(())
    }
}

public extension WhooshingClient {
    func get(
        _ url: WebURI,
        body: HTTPBody? = nil,
        headers: HTTPHeaders = [:],
        afterSend: @escaping AfterSendAction = defaultAfterSend
    ) -> EventLoopFuture<HTTPResponse> {
        send(.GET, to: url, body: body, headers: headers, afterSend: afterSend)
    }
    
    func post(
        _ url: WebURI,
        body: HTTPBody? = nil,
        headers: HTTPHeaders = [:],
        afterSend: @escaping AfterSendAction = defaultAfterSend
    ) -> EventLoopFuture<HTTPResponse> {
        send(.POST, to: url, body: body, headers: headers, afterSend: afterSend)
    }
    
    func patch(
        _ url: WebURI,
        body: HTTPBody? = nil,
        headers: HTTPHeaders = [:],
        afterSend: @escaping AfterSendAction = defaultAfterSend
    ) -> EventLoopFuture<HTTPResponse> {
        send(.PATCH, to: url, body: body, headers: headers, afterSend: afterSend)
    }
    
    func put(
        _ url: WebURI,
        body: HTTPBody? = nil,
        headers: HTTPHeaders = [:],
        afterSend: @escaping AfterSendAction = defaultAfterSend
    ) -> EventLoopFuture<HTTPResponse> {
        send(.PUT, to: url, body: body, headers: headers, afterSend: afterSend)
    }
    
    func delete(
        _ url: WebURI,
        body: HTTPBody? = nil,
        headers: HTTPHeaders = [:],
        afterSend: @escaping AfterSendAction = defaultAfterSend
    ) -> EventLoopFuture<HTTPResponse> {
        send(.DELETE, to: url, body: body, headers: headers, afterSend: afterSend)
    }
    
    func send(
        _ method: HTTPMethod,
        to url: WebURI,
        body: HTTPBody? = nil,
        headers: HTTPHeaders = [:],
        afterSend: @escaping AfterSendAction = defaultAfterSend
    ) -> EventLoopFuture<HTTPResponse> {
        let request = HTTPRequest(method: method, url: url, headers: headers, body: body)
        return send(request, afterSend: afterSend)
    }
}
