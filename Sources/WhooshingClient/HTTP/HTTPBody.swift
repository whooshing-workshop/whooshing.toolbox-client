import NIOCore
import AsyncAlgorithms
import NIOHTTP1

/// 一个 HTTP 请求或响应的主体。
///
/// HTTP 请求或响应 的数据体均支持 二进制数据 或 数据流式传输，该类型允许
/// 将数据以不同的类型写入一个请求，该类型将自动编码或解码并自动附带适当的 HTTP 头
/// 信息（如 Content-Type）
///
/// #### 创建文字内容的 Body：
/// ```swift
/// let body = try HTTPBody.text("Hello, world!")
/// ```
///
/// #### 创建 JSON 请求体：
/// ```swift
/// struct User: Codable { var name: String }
/// let body = try HTTPBody.json(User(name: "Alice"))
/// ```
///
/// #### 从 ByteBuffer 创建：
/// ```swift
/// let buffer = ByteBuffer(string: "raw data")
/// let body = HTTPBody.bytes(buffer)
/// ```
///
/// #### 从 Body 解码为字符串：
/// ```swift
/// let text = try body.text()
/// ```
///
/// #### 从 Body 解码为模型：
/// ```swift
/// let user = try body.json(as: User.self)
/// ```
///
/// #### 创建流式 JSON 数据：
/// ```swift
/// let stream = AsyncThrowingChannel<User, Error>()
/// let body = HTTPBody.jsonStream(stream)
/// ```
/// #### 将文件写入请求体:
///
/// ```swift
/// let fileBody = HTTPBody.file(from: "input.dat")
/// ```
///
/// #### 将流式请求体写入文件：
/// ```swift
/// try await body.file(to: "output.dat")
/// ```
@frozen
public struct HTTPBody: Sendable {
    /// HTTP 内容的类型，支持静态字节或异步流。
    public enum `Type`: Sendable {
        /// 以 `ByteBuffer` 表示的静态内容，适合小型请求体。
        case bytes(ByteBuffer)
        /// 以异步通道形式表示的流式内容，适合大文件或分块传输。
        case stream(AsyncThrowingChannel<ByteBuffer, Error>)
    }
    
    public let type: `Type`
    public let headers: HTTPHeaders
    
    /// 初始化 HTTPBody 实例
    ///
    /// 非公开初始化函数，你应当使用 `HTTPBody+Encode` 或 `HTTPBody+Decode` 中的扩展方法初始化
    ///
    /// - Parameters:
    ///   - type: 主体类型，可以是静态数据或异步流。
    ///   - headers: 与主体关联的 HTTP 头部，默认 Content-Type 为 `application/octet-stream`。
    @inlinable
    init(type: `Type`, headers: HTTPHeaders = ["content-type": "application/octet-stream"]) {
        self.type = type
        self.headers = headers
    }
}
