import NIOHTTP1
import NIOCore
import ErrorHandle
import Foundation
import AsyncHTTPClient

#if WHOOSHING_VAPOR
import Vapor
#endif

/// 表示一个 HTTP 请求，封装了请求方法、URL、HTTP 版本、头部信息、请求体以及相关的 NIO 通道。
/// 该结构用于在客户端或服务端构建和解析 HTTP 请求。
public struct HTTPRequest: Sendable, CustomStringConvertible {
    
    /// HTTP 请求方法，例如 GET、POST、PUT 等。
    public var method: HTTPMethod
    /// 请求的目标 URL，使用 WebURI 类型进行封装。
    public var url: WebURI
    /// HTTP 协议版本，默认是 HTTP/1.1。
    public var version: HTTPVersion
    /// HTTP 请求头，用于传递元信息，例如 Content-Type、Authorization 等。
    public var headers: HTTPHeaders
    /// 与该请求关联的 NIO 通道，可能为 nil。用于底层网络通信上下文。
    public weak var channel: Channel?
    
    public var body: HTTPBody? {
        willSet {
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
                if let body = body {
                    for (name, _) in body.headers {
                        self.headers.remove(name: name)
                    }
                }
            }
        }
    }
    
    /// 请求的字符串描述，包含请求行、头部和正文，用于日志或调试输出。
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
    
    /// 将 HTTPRequest 转换为字节缓冲区形式，便于通过底层网络传输。
    ///
    /// - Parameter bufferAllocator: ByteBuffer 分配器，默认新建一个。
    /// - Returns: 一个元组，第一个元素是包含请求行和头部的 ByteBuffer，第二个是可选的正文 ByteBuffer。
    /// - Throws: 若转换过程中出现错误，可能抛出异常。
    public func headData(allocator: ByteBufferAllocator = .init()) -> ByteBuffer {
        var requestStr = "\(method.rawValue) \(url) HTTP/1.1\r\n"
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
    
    /// 定义了 HTTPRequest 中可能抛出的错误，用于统一错误处理。
    public enum Err: String, ErrList {
        public var domain: String { "woo.sys.client.request.err" }
        case requestToDataFailed = "将请求转为 Data 失败"
    }
}
