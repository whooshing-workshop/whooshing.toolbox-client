import Cryptos
import NIOCore
import NIOHTTP1

/// 客户端协议，定义了与服务器交互的各种方法
public protocol WhooshingClient: AnyObject,Sendable {
    
    /// 用于文件操作的EventLoop
    var fileEventLoop: EventLoop { get }
    var key: Crypto.Symm.Key? { get }
    var channel: (any Channel)? { get }
    func removeHTTPHandlers() async throws
    func removeHTTPHandlers(in eventLoop: any EventLoop) -> EventLoopFuture<Void>
    
    // MARK: - 核心实现
    func get(_ url: WebURI, body: HTTPBody?, headers: HTTPHeaders) -> EventLoopFuture<HTTPResponse>
    func post(_ url: WebURI, body: HTTPBody?, headers: HTTPHeaders) -> EventLoopFuture<HTTPResponse>
    func patch(_ url: WebURI, body: HTTPBody?, headers: HTTPHeaders) -> EventLoopFuture<HTTPResponse>
    func put(_ url: WebURI, body: HTTPBody?, headers: HTTPHeaders) -> EventLoopFuture<HTTPResponse>
    func delete(_ url: WebURI, body: HTTPBody?, headers: HTTPHeaders) -> EventLoopFuture<HTTPResponse>
    func send(_ method: HTTPMethod, to url: WebURI, body: HTTPBody?, headers: HTTPHeaders) -> EventLoopFuture<HTTPResponse>

    /// 核心发送方法
    func send(_ request: HTTPRequest) -> EventLoopFuture<HTTPResponse>
}

public extension WhooshingClient {
    func get(
        _ url: WebURI,
        body: HTTPBody? = nil,
        headers: HTTPHeaders = [:]
    ) -> EventLoopFuture<HTTPResponse> {
        send(.GET, to: url, body: body, headers: headers)
    }
    
    func post(
        _ url: WebURI,
        body: HTTPBody? = nil,
        headers: HTTPHeaders = [:]
    ) -> EventLoopFuture<HTTPResponse> {
        send(.POST, to: url, body: body, headers: headers)
    }
    
    func patch(
        _ url: WebURI,
        body: HTTPBody? = nil,
        headers: HTTPHeaders = [:]
    ) -> EventLoopFuture<HTTPResponse> {
        send(.PATCH, to: url, body: body, headers: headers)
    }
    
    func put(
        _ url: WebURI,
        body: HTTPBody? = nil,
        headers: HTTPHeaders = [:]
    ) -> EventLoopFuture<HTTPResponse> {
        send(.PUT, to: url, body: body, headers: headers)
    }
    
    func delete(
        _ url: WebURI,
        body: HTTPBody? = nil,
        headers: HTTPHeaders = [:]
    ) -> EventLoopFuture<HTTPResponse> {
        send(.DELETE, to: url, body: body, headers: headers)
    }
    
    func send(
        _ method: HTTPMethod,
        to url: WebURI,
        body: HTTPBody? = nil,
        headers: HTTPHeaders = [:]
    ) -> EventLoopFuture<HTTPResponse> {
        let request = HTTPRequest(method: method, url: url, headers: headers, body: body)
        return send(request)
    }
}
