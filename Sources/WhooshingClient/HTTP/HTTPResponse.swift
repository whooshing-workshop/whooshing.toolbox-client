import NIOHTTP1
import NIOCore
import ErrorHandle
import Foundation
import AsyncHTTPClient

/// 表示一个 HTTP 响应，包含状态码、版本、头部信息、正文内容和相关通道。
/// 适用于客户端与服务端的 HTTP 响应处理和构造。
public struct HTTPResponse: Sendable, CustomStringConvertible {
    
    /// HTTP 协议版本，默认为 HTTP/1.1。
    public var version: HTTPVersion
    /// HTTP 响应状态，例如 200 OK、404 Not Found。
    public var status: HTTPResponseStatus
    /// HTTP 响应头，用于包含响应的元信息，例如 Content-Type。
    public var headers: HTTPHeaders
    /// 与响应相关联的底层 NIO 通道（可选），用于网络上下文。
    public weak var channel: Channel?
    
    /// 请求体内容。设置此值时会自动更新相关头部字段：
    /// - 若为 `.bytes` 类型，则写入 `content-length` 并移除 `transfer-encoding`；
    /// - 若为 `.stream` 类型，则写入 `transfer-encoding: chunked` 并移除 `content-length`；
    /// - 若设置为 `nil`，则默认写入 `content-length: 0`，并移除已有的 `content` 相关头字段。
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
    
    private var __body: HTTPBody?
        
    /// 响应的字符串描述，包括状态行、头部信息和正文，适用于调试或日志记录。
    public var description: String {
        let statusLine = "HTTP/\(version.major).\(version.minor) \(status.code) \(status.reasonPhrase)\r\n"

        var headerLines = headers.map { "\($0.name): \($0.value)" }.joined(separator: "\r\n")
        if !headerLines.isEmpty {
            headerLines += "\r\n"
        }

        let bodyString: String
        if case let .bytes(body) = self.body?.type, body.readableBytes > 0 {
            var copy = body
            bodyString = copy.readString(length: copy.readableBytes) ?? ""
        } else {
            bodyString = ""
        }

        return statusLine + headerLines + "\r\n" + bodyString
    }
    
    /// 创建一个新的 HTTPResponse 实例。
    ///
    /// - Parameters:
    ///   - status: HTTP 状态码。
    ///   - body: 响应体内容，默认为 nil。
    ///   - version: 协议版本，默认为 HTTP/1.1。
    ///   - headers: 响应头，默认为空。
    public init(
        status: HTTPResponseStatus,
        body: HTTPBody? = nil,
        version: HTTPVersion = .http1_1,
        headers: HTTPHeaders = [:]
    ) {
        self.status = status
        self.version = version
        self.headers = headers
        self.body = body
    }
    
    /// 定义 HTTPResponse 中可能出现的错误，用于响应解析失败处理。
    enum Err: String, ErrList {
        var domain: String { "woo.sys.client.response.err" }
        case responseParseFailed = "响应解析失败"
        case unknowErr = "解析响应时出现未知错误"
    }
}
