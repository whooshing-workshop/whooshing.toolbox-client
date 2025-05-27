import NIOHTTP1
import NIOCore
import ErrorHandle
import Foundation
import AsyncHTTPClient

#if WHOOSHING_VAPOR
import Vapor
#endif

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
   
    /// 从 ByteBuffer 中解析构造 HTTPResponse 实例。
    ///
    /// - Parameter data: 包含完整响应内容的字节缓冲。
    /// - Throws: 如果解析失败，抛出相关错误。
    public init(data: ByteBuffer) throws {
        var responseData = data
        var (header, body) = try Self.parseHTTPResponse(from: &responseData)
        guard let headerStr = header.readString(length: header.readableBytes) else { throw Err.responseParseFailed.d("无法将请求转为 String", 10070) }
        let headers = headerStr.components(separatedBy: "\r\n")
        // Headers 解析
        guard headers.count >= 1 else { throw Err.responseParseFailed.d("格式不正确，无效的 Header", 10072) }
        let requestLine = headers[0].components(separatedBy: " ")
        guard requestLine.count >= 3 else { throw Err.responseParseFailed.d("第一行 Header 格式不正确", 10073) }
        let version = try Self.parseHTTPVersion(requestLine[0])
        guard let statusCode = Int(requestLine[1]) else { throw Err.responseParseFailed.d("状态码无效", 10074) }
        let status = HTTPResponseStatus(statusCode: statusCode, reasonPhrase: requestLine[2])
        var hs: [(String, String)] = []
        for (i, h) in headers.enumerated() {
            if i == 0 { continue }
            let comps = h.components(separatedBy: ": ")
            guard comps.count == 2 else { throw Err.responseParseFailed.d("Header 解析失败：格式不正确", 10075) }
            hs.append((comps[0], comps[1]))
        }
        self.version = version
        self.status = status
        self.headers = .init(hs)
        
        if let body = body {
            self.body = body.readableBytes == 0 ? nil : .bytes(body)
        } else {
            self.body = nil
        }
    }
    
    /// 解析 HTTP 协议版本字符串，转换为 HTTPVersion 实例。
    ///
    /// - Parameter versionString: 形如 "HTTP/1.1" 的版本字符串。
    /// - Returns: HTTPVersion 对象。
    /// - Throws: 如果格式不正确或转换失败，抛出异常。
    static private func parseHTTPVersion(_ versionString: String) throws -> HTTPVersion {
        // 检查前缀是否为 "HTTP/"
        guard versionString.hasPrefix("HTTP/") else {
            throw Err.responseParseFailed.d("HTTP 协议版本号不正确，得到 \(versionString)", 14081)
        }

        // 去掉 "HTTP/" 前缀后切分版本号部分
        let versionPart = versionString.dropFirst(5) // "1.1"
        let components = versionPart.split(separator: ".")

        // 检查是否有两个数字部分
        guard components.count == 2,
              let major = Int(components[0]),
              let minor = Int(components[1]) else {
            throw Err.responseParseFailed.d("HTTP 协议版本号不正确，未解析得到数字，得到 \(versionString)", 14082)
        }

        return HTTPVersion(major: major, minor: minor)
    }
   
    /// 从 ByteBuffer 中提取 HTTP 响应的头部和正文内容。
    ///
    /// - Parameter buffer: 完整响应数据。
    /// - Returns: 包含头部和正文的元组。
    /// - Throws: 如果格式不正确或提取失败，抛出错误。
    static private func parseHTTPResponse(from buffer: inout ByteBuffer) throws -> (headers: ByteBuffer, body: ByteBuffer?) {
        // 查找请求头和请求体的分隔符 `\r\n\r\n`
        if let headerEndIndex = findHeaderEndIndex(in: buffer) {
            guard let headers = buffer.readSlice(length: headerEndIndex) else { throw Err.unknowErr.d("无法获得 Header 数据片", 10076) }
            buffer.moveReaderIndex(forwardBy: 4)
            guard let body = buffer.readSlice(length: buffer.readableBytes) else { throw Err.unknowErr.d("找到了分隔符，却无法获得 Body 数据片", 10077) }
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
                if slice == searchPattern { return index - buffer.readerIndex }
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

#if WHOOSHING_VAPOR

extension HTTPResponse: AsyncResponseEncodable {
    public func encodeResponse(for request: Request) async throws -> Response {
        return try await encodeResponse(for: request).get()
    }
}

extension HTTPResponse: ResponseEncodable {
    public func encodeResponse(for request: Request) -> EventLoopFuture<Response> {
        request.eventLoop.makeFutureWithTask {
            let b: Response.Body
            if let body = self.body {
                switch body {
                case .bytes(let bytes): b = .init(buffer: bytes)
                case .stream(let asyncBytes):
                    b = .init(asyncStream: { writer in
                        for try await chunk in asyncBytes {
                            try await writer.write(.buffer(chunk))
                        }
                    })
                }
            } else {
                b = .empty
            }
            let response = Response(
                status: self.status,
                version: self.version,
                headers: self.headers,
                body: b
            )
        }
    }
}

#endif
