import NIOHTTP1
import NIOCore
import ErrorHandle
import Foundation

#if WHOOSHING_VAPOR
import Vapor
#endif

public struct HTTPRequest: Sendable, CustomStringConvertible, BodyCodable {
    public var method: HTTPMethod
    public var url: WebURI
    public var version: HTTPVersion
    public var headers: HTTPHeaders
    public var body: ByteBuffer?
    public weak var channel: Channel?
    
    public var description: String {
        let requestLine = "\(method.rawValue) \(url.path) HTTP/\(version.major).\(version.minor)\r\n"
        
        var headerLines = headers.map { "\($0.name): \($0.value)" }.joined(separator: "\r\n")
        if !headerLines.isEmpty { headerLines += "\r\n" }
        
        let bodyString: String
        if let body = body, body.readableBytes > 0 {
            var copy = body
            bodyString = copy.readString(length: copy.readableBytes) ?? ""
        } else {
            bodyString = ""
        }
        
        return requestLine + headerLines + "\r\n" + bodyString
    }
    
    public func data(bufferAllocator: ByteBufferAllocator = .init()) throws -> (ByteBuffer, ByteBuffer?) {
        var buffer = bufferAllocator.buffer(capacity: 0)
        let requestLine = "\(method.rawValue) \(url.path) HTTP/\(version.major).\(version.minor)\r\n"
        buffer.writeString(requestLine)
        headers.forEach { (name, value) in buffer.writeString("\(name): \(value)\r\n") }
        buffer.writeString("\r\n")
        return (buffer, body)
    }
    
    public init(
        method: HTTPMethod,
        url: WebURI,
        version: HTTPVersion = .http1_1,
        headers: HTTPHeaders = [:],
        body: ByteBuffer? = nil
    ) {
        self.method = method
        self.url = url
        self.version = version
        self.headers = headers
        self.body = body
    }
    
    public enum Err: String, ErrList {
        public var domain: String { "woo.sys.client.request.err" }
        case requestToDataFailed = "将请求转为 Data 失败"
    }
}

extension HTTPRequest: Codable {
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        method = try container.decode(HTTPMethod.self, forKey: .method)
        url = try container.decode(WebURI.self, forKey: .url)
        version = try container.decode(HTTPVersion.self, forKey: .version)
        headers = try container.decode(HTTPHeaders.self, forKey: .headers)
        body = try container.decode(ByteBuffer?.self, forKey: .body)
        channel = nil
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(method, forKey: .method)
        try container.encode(url, forKey: .url)
        try container.encode(version, forKey: .version)
        try container.encode(headers, forKey: .headers)
        try container.encode(body, forKey: .body)
    }

    private enum CodingKeys: String, CodingKey {
        case method
        case url
        case version
        case headers
        case body
    }
}
