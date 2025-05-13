import NIOHTTP1
import NIOCore
import ErrorHandle
import Foundation

public struct HTTPResponse: Sendable, CustomStringConvertible, BodyCodable {
    public var version: HTTPVersion
    public var status: HTTPResponseStatus
    public var headers: HTTPHeaders
    public var body: ByteBuffer?
    public weak var channel: Channel?
        
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
    
    // 解析 HTTP 版本号
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
   
   // 解析 HTTP 响应，分割请求头和请求体
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
   
    // 查找响应头结束的位置（即 \r\n\r\n）
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
    
    enum Err: String, ErrList {
        var domain: String { "woo.sys.client.response.err" }
        case responseParseFailed = "响应解析失败"
        case unknowErr = "解析响应时出现未知错误"
    }
}

extension HTTPResponse: Codable {
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        version = try container.decode(HTTPVersion.self, forKey: .version)
        status = try container.decode(HTTPResponseStatus.self, forKey: .status)
        headers = try container.decode(HTTPHeaders.self, forKey: .headers)
        body = try container.decode(ByteBuffer?.self, forKey: .body)
        channel = nil
    }

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
