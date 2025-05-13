import NIOHTTP1
import NIOCore
import ErrorHandle
import Foundation

#if WHOOSHING_VAPOR
import Vapor
#endif

/// 表示一个 HTTP 响应，包含状态码、版本、头部信息、正文内容和相关通道。
/// 适用于客户端与服务端的 HTTP 响应处理和构造。
public struct HTTPResponse: Sendable, CustomStringConvertible, BodyCodable {
    /// HTTP 协议版本，默认为 HTTP/1.1。
    public var version: HTTPVersion
    /// HTTP 响应状态，例如 200 OK、404 Not Found。
    public var status: HTTPResponseStatus
    /// HTTP 响应头，用于包含响应的元信息，例如 Content-Type。
    public var headers: HTTPHeaders
    /// HTTP 响应体内容，通常为 HTML、JSON 等。
    public var body: ByteBuffer?
    /// 与响应相关联的底层 NIO 通道（可选），用于网络上下文。
    public weak var channel: Channel?
        
    /// 响应的字符串描述，包括状态行、头部信息和正文，适用于调试或日志记录。
    public var description: String {
        let statusLine = "HTTP/\(version.major).\(version.minor) \(status.code) \(status.reasonPhrase)\r\n"

        var headerLines = headers.map { "\($0.name): \($0.value)" }.joined(separator: "\r\n")
        if !headerLines.isEmpty {
            headerLines += "\r\n"
        }

        let bodyString: String
        if let body = body, body.readableBytes > 0 {
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
        body: ByteBuffer? = nil,
        version: HTTPVersion = .http1_1,
        headers: HTTPHeaders = [:]
    ) {
        self.status = status
        self.body = body
        self.version = version
        self.headers = headers
    }
   
    /// 从 ByteBuffer 中解析构造 HTTPResponse 实例。
    ///
    /// - Parameter data: 包含完整响应内容的字节缓冲。
    /// - Throws: 如果解析失败，抛出相关错误。
    public init(data: ByteBuffer) throws {
        var (header, body) = try Self.parseHTTPResponse(from: data)
        guard let headers = header.readString(length: header.readableBytes)?.components(separatedBy: "\r\n") else { throw Err.responseParseFailed.d("无法将请求转为 String", 10070, (#file, #line)) }
        // Headers 解析
        guard headers.count >= 1 else { throw Err.responseParseFailed.d("格式不正确，无效的 Header", 10072, (#file, #line)) }
        let requestLine = headers[0].components(separatedBy: " ")
        guard requestLine.count >= 3 else { throw Err.responseParseFailed.d("第一行 Header 格式不正确", 10073, (#file, #line)) }
        let version = try Self.parseHTTPVersion(requestLine[0])
        guard let statusCode = Int(requestLine[1]) else { throw Err.responseParseFailed.d("状态码无效", 10074, (#file, #line)) }
        let status = HTTPResponseStatus(statusCode: statusCode, reasonPhrase: requestLine[2])
        var hs: [(String, String)] = []
        for (i, h) in headers.enumerated() {
            if i == 0 { continue }
            let comps = h.components(separatedBy: ": ")
            guard comps.count == 2 else { throw Err.responseParseFailed.d("Header 解析失败：格式不正确", 10075, (#file, #line)) }
            hs.append((comps[0], comps[1]))
        }
        self.version = version
        self.status = status
        self.headers = .init(hs)
        self.body = body
    }
    
    /// 解析 HTTP 协议版本字符串，转换为 HTTPVersion 实例。
    ///
    /// - Parameter versionString: 形如 "HTTP/1.1" 的版本字符串。
    /// - Returns: HTTPVersion 对象。
    /// - Throws: 如果格式不正确或转换失败，抛出异常。
    static private func parseHTTPVersion(_ versionString: String) throws -> HTTPVersion {
        // 检查前缀是否为 "HTTP/"
        guard versionString.hasPrefix("HTTP/") else {
            throw Err.responseParseFailed.d("HTTP 协议版本号不正确，得到 \(versionString)", 14081, (#file, #line))
        }

        // 去掉 "HTTP/" 前缀后切分版本号部分
        let versionPart = versionString.dropFirst(5) // "1.1"
        let components = versionPart.split(separator: ".")

        // 检查是否有两个数字部分
        guard components.count == 2,
              let major = Int(components[0]),
              let minor = Int(components[1]) else {
            throw Err.responseParseFailed.d("HTTP 协议版本号不正确，未解析得到数字，得到 \(versionString)", 14082, (#file, #line))
        }

        return HTTPVersion(major: major, minor: minor)
    }
   
    /// 从 ByteBuffer 中提取 HTTP 响应的头部和正文内容。
    ///
    /// - Parameter buffer: 完整响应数据。
    /// - Returns: 包含头部和正文的元组。
    /// - Throws: 如果格式不正确或提取失败，抛出错误。
    static private func parseHTTPResponse(from buffer: ByteBuffer) throws -> (headers: ByteBuffer, body: ByteBuffer?) {
        // 查找请求头和请求体的分隔符 `\r\n\r\n`
        if let headerEndIndex = findHeaderEndIndex(in: buffer) {
            guard let headers = buffer.getSlice(at: buffer.readerIndex, length: headerEndIndex) else { throw Err.unknowErr.d("无法获得 Header 数据片", 10076, (#file, #line)) }
            // +4 是跳过 \r\n\r\n
            guard let body = buffer.getSlice(at: headerEndIndex + 4, length: buffer.readableBytes - (headerEndIndex + 4)) else { throw Err.unknowErr.d("找到了分隔符，却无法获得 Body 数据片", 10077, (#file, #line)) }
            return (headers: headers, body: body)
        }

        // 表示没有找到分隔符，即没有 Body
        return (buffer, nil)
    }
   
    /// 查找 HTTP 响应头与正文之间的分隔位置（\r\n\r\n）。
    ///
    /// - Parameter buffer: 响应数据。
    /// - Returns: 分隔符在缓冲区中的索引；若未找到返回 nil。
    static private func findHeaderEndIndex(in buffer: ByteBuffer) -> Int? {
        let searchPattern: [UInt8] = [13, 10, 13, 10]  // \r\n\r\n
        var index = buffer.readerIndex

        // 持续查找直到 buffer 中没有足够的字节
        while index + 3 < buffer.readableBytes {
            // 获取当前位置的 4 字节
            if let slice = buffer.getBytes(at: index, length: 4) {
                // 比较这 4 字节是否等于 \r\n\r\n
                if slice == searchPattern { return index }
            }
            index += 1
        }
        return nil
    }
    
    /// 定义 HTTPResponse 中可能出现的错误，用于响应解析失败处理。
    enum Err: String, ErrList {
        var domain: String { "woo.sys.client.response.err" }
        case responseParseFailed = "响应解析失败"
        case unknowErr = "解析响应时出现未知错误"
    }
}

extension HTTPResponse: Codable {
    /// 从 Decoder 实例解码生成 HTTPResponse。
    ///
    /// - Parameter decoder: 用于解码的 Decoder 实例。
    /// - Throws: 解码失败时抛出异常。
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        version = try container.decode(HTTPVersion.self, forKey: .version)
        status = try container.decode(HTTPResponseStatus.self, forKey: .status)
        headers = try container.decode(HTTPHeaders.self, forKey: .headers)
        body = try container.decode(ByteBuffer?.self, forKey: .body)
        channel = nil
    }

    /// 将 HTTPResponse 编码为指定的 Encoder。
    ///
    /// - Parameter encoder: 用于编码的 Encoder 实例。
    /// - Throws: 编码失败时抛出异常。
    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(version, forKey: .version)
        try container.encode(status, forKey: .status)
        try container.encode(headers, forKey: .headers)
        try container.encode(body, forKey: .body)
    }

    private enum CodingKeys: String, CodingKey {
        case version
        case status
        case headers
        case body
    }
}
