import ErrorHandle
import Foundation

#if WHOOSHING_VAPOR
import Vapor
#endif

/// 表示一个 Web URI（统一资源标识符），支持标准的 HTTP/HTTPS/WS/WSS 协议解析与构造。
/// 提供便捷的字符串初始化、路径、查询参数、片段等组成部分访问功能。
/// 支持字符串字面量初始化、描述输出、序列化与发送。
public struct WebURI: CustomStringConvertible, ExpressibleByStringInterpolation, Codable, Sendable {
    
    /// Web URI 支持的协议方案，如 http、https、ws、wss。
    /// 枚举值直接对应协议字符串，便于统一管理与比较。
    public enum Scheme: String, Sendable, CustomStringConvertible, Codable {
        case http = "http"
        case https = "https"
        case ws = "ws"
        case wss = "wss"
        
        public var string: String { self.rawValue }
        public var description: String { self.rawValue }
    }
    
    /// URI 使用的协议方案（如 http、https 等）。
    public let scheme: Scheme
    /// URI 的主机名或 IP 地址。
    public let host: String
    /// 可选的端口号，若未指定则为协议默认端口。
    public let port: Int?
    /// URI 的路径部分，默认值为 "/"。
    public let path: String
    /// 可选的查询参数字符串，通常以 `key=value` 形式连接。
    public let query: String?
    /// 可选的 URI 片段标识符（#fragment）。
    public let fragment: String?
    /// 表示当前 WebURI 的完整字符串表示形式。
    /// 该值可能是从原始字符串初始化时保留的，也可能由结构体各字段拼接生成。
    /// 通常用于输出、日志、URL 请求构造等场景。
    public let string: String
    /// 表示放在 HTTP Request 中的 Path + Query 路径
    public let queryPath: String
    
    /// WebURI 的字符串描述，等价于其完整字符串形式。
    public var description: String { string }
    
    /// 允许通过字符串字面量（例如 "https://example.com"）创建 WebURI 实例。
    /// 如果解析失败会触发运行时崩溃。
    public init(stringLiteral value: String) {
        do {
            self = try Self(string: value)
        } catch {
            fatalError("\(error)")
        }
    }
    
    /// 通过原始 URL 字符串创建 WebURI 实例。
    ///
    /// - Parameter string: 标准 URI 字符串。
    /// - Throws: 如果字符串格式非法，将抛出 URI 解析失败错误。
    public init(string: String) throws {
        guard
            let url = URLComponents(string: string),
            let schemeStr = url.scheme?.lowercased(),
            let scheme = Scheme(rawValue: schemeStr),
            let host = url.host
        else {
            throw Err.parseFailed.d("所提供的 URI 不合法 (\(string))", 14080)
        }
        
        self.scheme = scheme
        self.host = host
        self.port = url.port
        self.path = url.path.isEmpty ? "/" : url.path
        self.query = url.query
        self.fragment = url.fragment
        self.string = Self.combineURI(scheme: scheme, host: host, port: self.port, path: self.path, query: self.query, fragment: self.fragment)
        self.queryPath = (url.path + (url.query == nil ? "" : "?\(url.query!)")).addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed)!
    }
    
    /// 根据各个组成部分构造 WebURI。
    ///
    /// - Parameters:
    ///   - scheme: 协议方案（http/https/ws/wss）。
    ///   - host: 主机名或 IP。
    ///   - port: 可选端口号。
    ///   - path: 路径部分，默认为 "/"。
    ///   - query: 查询参数键值对，默认空。
    ///   - fragment: URL 片段标识符，默认 nil。
    public init(
        scheme: Scheme,
        host: String,
        port: Int? = nil,
        path: String = "/",
        query: [String: String],
        fragment: String? = nil
    ) {
        let q = query.map { key, value in
            let encodedKey = key
            let encodedValue = value
            return "\(encodedKey)=\(encodedValue)"
        }.joined(separator: "&")
        
        self = Self(scheme: scheme, host: host, port: port, path: path, query: q.isEmpty ? nil : q, fragment: fragment)
    }
    
    /// 根据各个组成部分构造 WebURI。
    ///
    /// - Parameters:
    ///   - scheme: 协议方案（http/https/ws/wss）。
    ///   - host: 主机名或 IP。
    ///   - port: 可选端口号。
    ///   - path: 路径部分，默认为 "/"。
    ///   - query: 查询参数，默认为 nil。
    ///   - fragment: URL 片段标识符，默认 nil。
    public init(
        scheme: Scheme,
        host: String,
        port: Int? = nil,
        path: String = "/",
        query: String? = nil,
        fragment: String? = nil
    ) {
        
        self.scheme = scheme
        self.host = host
        self.port = port
        self.path = path.isEmpty ? "/" : path
        self.query = (query == nil || query!.isEmpty) ? nil : query!
        self.fragment = fragment
        
        self.string = Self.combineURI(scheme: scheme, host: host, port: port, path: path, query: self.query, fragment: fragment)
        self.queryPath = (path + (self.query == nil ? "" : "?\(self.query!)")).addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed)!
    }
    
    /// URI 解析过程中可能抛出的错误类型。
    /// 用于指示非法格式的 URI 字符串。
    public enum Err: String, ErrList {
        public var domain: String { "woo.sys.client.uri.err" }
        case parseFailed = "URI 解析失败"
    }
    
    /// 判断当前 host 是否为域名而非 IP 地址。
    ///
    /// - Returns: 如果 host 是标准域名（非 IP 或 localhost），返回 true。
    public func isDomainHost() -> Bool {
        if host == "localhost" { return false }
        let parts = host.split(separator: ".")
        guard parts.count == 4 else { return true }
        return parts.allSatisfy { part in
            if let num = Int(part), (0...255).contains(num) {
                return false
            }
            return true
        }
    }
    
    private static func combineURI(scheme: Scheme, host: String, port: Int?, path: String, query: String?, fragment: String?) -> String {
        var res = "\(scheme)://\(host)"
        if let port = port { res += ":\(port)" }
        res += "\(path.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "/")"
        if let q = query?.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) { res += "?\(q)" }
        if let fragment = fragment?.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) { res += "#\(fragment)" }
        return res
    }
}

#if WHOOSHING_VAPOR

public extension WebURI {
    var uri: URI {
        .init(stringLiteral: self.string)
    }
}

#endif
