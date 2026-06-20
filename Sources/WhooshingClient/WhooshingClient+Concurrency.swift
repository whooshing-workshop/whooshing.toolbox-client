import NIOCore
import NIOHTTP1
import NIOAdvanced

public extension WhooshingClient {
    /// 发送一个异步阻塞 GET 请求。
    ///
    /// - Parameters:
    ///   - url: 请求的目标地址。
    ///   - body: 可选的请求体内容。
    ///   - headers: 要附加的 HTTP 请求头，默认为空。
    /// - Returns: HTTP 响应对象。
    /// - Throws: 请求发送失败时抛出错误。
    @inlinable
    func get(
        _ url: WebURI,
        body: HTTPBody? = nil,
        headers: HTTPHeaders = [:]
    ) async throws(Failure) -> HTTPResponse {
        try await send(.GET, to: url, body: body, headers: headers)
    }
    
    /// 发送一个异步阻塞 POST 请求。
    ///
    /// - Parameters:
    ///   - url: 请求的目标地址。
    ///   - body: 可选的请求体内容。
    ///   - headers: 要附加的 HTTP 请求头，默认为空。
    /// - Returns: HTTP 响应对象。
    /// - Throws: 请求发送失败时抛出错误。
    @inlinable
    func post(
        _ url: WebURI,
        body: HTTPBody? = nil,
        headers: HTTPHeaders = [:]
    ) async throws(Failure) -> HTTPResponse {
        try await send(.POST, to: url, body: body, headers: headers)
    }
    
    /// 发送一个异步阻塞 PATCH 请求。
    ///
    /// - Parameters:
    ///   - url: 请求的目标地址。
    ///   - body: 可选的请求体内容。
    ///   - headers: 要附加的 HTTP 请求头，默认为空。
    /// - Returns: HTTP 响应对象。
    /// - Throws: 请求发送失败时抛出错误。
    @inlinable
    func patch(
        _ url: WebURI,
        body: HTTPBody? = nil,
        headers: HTTPHeaders = [:]
    ) async throws(Failure) -> HTTPResponse {
        try await send(.PATCH, to: url, body: body, headers: headers)
    }
    
    /// 发送一个异步阻塞 PUT 请求。
    ///
    /// - Parameters:
    ///   - url: 请求的目标地址。
    ///   - body: 可选的请求体内容。
    ///   - headers: 要附加的 HTTP 请求头，默认为空。
    /// - Returns: HTTP 响应对象。
    /// - Throws: 请求发送失败时抛出错误。
    @inlinable
    func put(
        _ url: WebURI,
        body: HTTPBody? = nil,
        headers: HTTPHeaders = [:]
    ) async throws(Failure) -> HTTPResponse {
        try await send(.PUT, to: url, body: body, headers: headers)
    }
    
    /// 发送一个异步阻塞 DELETE 请求。
    ///
    /// - Parameters:
    ///   - url: 请求的目标地址。
    ///   - body: 可选的请求体内容。
    ///   - headers: 要附加的 HTTP 请求头，默认为空。
    /// - Returns: HTTP 响应对象。
    /// - Throws: 请求发送失败时抛出错误。
    @inlinable
    func delete(
        _ url: WebURI,
        body: HTTPBody? = nil,
        headers: HTTPHeaders = [:]
    ) async throws(Failure) -> HTTPResponse {
        try await send(.DELETE, to: url, body: body, headers: headers)
    }
    
    /// 发送一个带指定 HTTP 方法的异步阻塞请求。
    ///
    /// - Parameters:
    ///   - method: 要使用的 HTTP 方法（如 GET、POST）。
    ///   - url: 请求的目标地址。
    ///   - body: 可选的请求体内容。
    ///   - headers: 要附加的 HTTP 请求头，默认为空。
    /// - Returns: HTTP 响应对象。
    /// - Throws: 请求发送失败或响应解析失败时抛出错误。
    @inlinable
    func send(
        _ method: HTTPMethod,
        to url: WebURI,
        body: HTTPBody? = nil,
        headers: HTTPHeaders = [:]
    ) async throws(Failure) -> HTTPResponse {
        let request = HTTPRequest(method: method, url: url, headers: headers, body: body)
        return try await send(request).get()
    }
}
