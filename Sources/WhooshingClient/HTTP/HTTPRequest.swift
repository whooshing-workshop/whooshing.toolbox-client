import NIOHTTP1
import NIOCore
import Foundation
import AsyncHTTPClient
import LoggingAdvanced

/// 表示一个 HTTP 请求，封装了请求方法、URL、版本、头部和请求体，
/// 提供便于在客户端或服务器中构建、序列化、调试 HTTP 请求的接口。
@frozen
public struct HTTPRequest: Sendable {
    
    /// HTTP 请求方法，例如 GET、POST、PUT 等。
    public var method: HTTPMethod
    /// 请求的目标 URL，使用 WebURI 类型进行封装。
    public var url: WebURI
    /// HTTP 协议版本，默认是 HTTP/1.1。
    public var version: HTTPVersion
    /// HTTP 请求头，用于传递元信息，例如 Content-Type、Authorization 等。
    public var headers: HTTPHeaders
    
    /// 请求体内容。设置此值时会自动更新相关头部字段：
    /// - 若为 `.bytes` 类型，则写入 `content-length` 并移除 `transfer-encoding`；
    /// - 若为 `.stream` 类型，则写入 `transfer-encoding: chunked` 并移除 `content-length`；
    /// - 若设置为 `nil`，则默认写入 `content-length: 0`，并移除已有的 `content` 相关头字段。
    @inlinable
    public var body: HTTPBody? {
        get { __body }
        set {
            if let body = newValue {
                switch body.type {
                case .bytes(let bytes):
                    self.headers.remove(name: "transfer-encoding")
                    self.headers.replaceOrAdd(name: "content-length", value: String(bytes.readableBytes))
                case .stream:
                    self.headers.remove(name: "content-length")
                    self.headers.replaceOrAdd(name: "transfer-encoding", value: "chunked")
                }
                for (name, value) in body.headers {
                    self.headers.replaceOrAdd(name: name, value: value)
                }
            } else {
                self.headers.remove(name: "transfer-encoding")
                self.headers.replaceOrAdd(name: "content-length", value: "0")
                if let body = __body {
                    for (name, _) in body.headers {
                        self.headers.remove(name: name)
                    }
                }
            }
            __body = newValue
        }
    }
    
    /// 内部存储的请求体，供外部 `body` 属性代理访问。
    @usableFromInline
    private(set) var __body: HTTPBody?
    
    /// 将 HTTPRequest 转换为字节缓冲区形式，便于通过底层网络传输。
    ///
    /// - Parameter bufferAllocator: ByteBuffer 分配器，默认新建一个。
    /// - Returns: 一个元组，第一个元素是包含请求行和头部的 ByteBuffer，第二个是可选的正文 ByteBuffer。
    /// - Throws: 若转换过程中出现错误，可能抛出异常。
    @inlinable
    public func headData(allocator: ByteBufferAllocator = .init()) -> ByteBuffer {
        var requestStr = "\(method.rawValue) \(url.queryPath) HTTP/1.1\r\n"
        headers.forEach { (name, value) in requestStr += "\(name): \(value)\r\n" }
        requestStr += "\r\n"
        let buffer = allocator.buffer(string: requestStr)
        return buffer
    }
    
    /// 创建一个新的 HTTPRequest 实例。
    ///
    /// - Parameters:
    ///   - method: HTTP 方法，例如 GET、POST 等。
    ///   - url: 请求的目标 URL。
    ///   - version: HTTP 协议版本，默认为 HTTP/1.1。
    ///   - headers: 请求头，默认为空。
    ///   - body: 请求体，默认为 nil。
    @inlinable
    public init(
        method: HTTPMethod,
        url: WebURI,
        version: HTTPVersion = .http1_1,
        headers: HTTPHeaders = [:],
        body: HTTPBody? = nil
    ) {
        self.method = method
        self.url = url
        self.version = version
        self.headers = headers
        self.body = body
    }
}

extension HTTPRequest: CustomStringConvertible, Loggerable {
    /// 返回请求的完整字符串表示，包含请求行、头部和正文内容（如为流则显示占位信息）。
    @inlinable
    public var description: String {
        let requestLine = "\(method.rawValue) \(url.queryPath) HTTP/\(version.major).\(version.minor)\r\n"
        
        var headerLines = headers.map { "\($0.name): \($0.value)" }.joined(separator: "\r\n")
        if !headerLines.isEmpty { headerLines += "\r\n" }
        
        let bodyString: String
        if case let .bytes(body) = self.body?.type, body.readableBytes > 0 {
            var copy = body
            bodyString = copy.readString(length: copy.readableBytes) ?? ""
        } else {
            bodyString = "<<async stream content>>"
        }
        
        return requestLine + headerLines + "\r\n" + bodyString
    }
}
