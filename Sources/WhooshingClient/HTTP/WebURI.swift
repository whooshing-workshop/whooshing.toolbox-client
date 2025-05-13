import ErrorHandle
import Foundation

public struct WebURI: CustomStringConvertible, ExpressibleByStringInterpolation, Codable, Sendable {
    
    public enum Scheme: String, Sendable, CustomStringConvertible, Codable {
        case http = "http"
        case https = "https"
        case ws = "ws"
        case wss = "wss"
        
        public var string: String { self.rawValue }
        public var description: String { self.rawValue }
    }
    
    public let scheme: Scheme
    public let host: String
    public let port: Int?
    public let path: String
    public let query: String?
    public let fragment: String?
    public let string: String
    
    public var description: String { string }
    
    public init(stringLiteral value: String) {
        do {
            self = try Self(string: value)
        } catch {
            fatalError("\(error)")
        }
    }
    
    public init(string: String) throws {
        guard
            let url = URLComponents(string: string),
            let schemeStr = url.scheme?.lowercased(),
            let scheme = Scheme(rawValue: schemeStr),
            let host = url.host
        else {
            throw Err.parseFailed.d("所提供的 URI 不合法 (\(string))", 14080, (#file, #line))
        }
        
        self.scheme = scheme
        self.host = host
        self.port = url.port
        self.path = url.path.isEmpty ? "/" : url.path
        self.query = url.query
        self.fragment = url.fragment
        self.string = string
    }
    
    public init(
        scheme: Scheme,
        host: String,
        port: Int? = nil,
        path: String = "/",
        query: [String: String] = [:],
        fragment: String? = nil
    ) {
        let q = query.map { key, value in
            let encodedKey = key.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? key
            let encodedValue = value.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? value
            return "\(encodedKey)=\(encodedValue)"
        }.joined(separator: "&")
        
        let p = path.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed)
        
        self.scheme = scheme
        self.host = host
        self.port = port
        self.path = (p == nil || p!.isEmpty) ? "/" : p!
        self.query = q.isEmpty ? nil : q
        self.fragment = fragment?.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed)
        
        var res = "\(scheme)://\(host)"
        if let port = port { res += ":\(port)" }
        res += "\(path)"
        if !q.isEmpty { res += "?\(q)" }
        if let fragment = fragment { res += "#\(fragment)" }
        
        self.string = res
    }
    
    public enum Err: String, ErrList {
        public var domain: String { "woo.sys.client.uri.err" }
        case parseFailed = "URI 解析失败"
    }
    
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
}
