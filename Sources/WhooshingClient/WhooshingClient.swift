import Vapor
import Cryptos
import ErrorHandle
import NIOConcurrencyHelpers
import NIO
import NIOFileSystem

/// 定义在发送请求前执行的操作闭包
/// - Parameters:
///   - request: 可变的客户端请求对象，用于修改请求内容
///   - channel: 用于发送请求的通道
public typealias BeforeSendAction = @Sendable (_ request: inout ClientRequest, _ channel: Channel) throws -> ()

/// 定义在发送请求后执行的操作闭包
/// - Parameter channel: 用于发送请求的通道
public typealias AfterSendAction =  @Sendable (_ channel: Channel) async throws -> ()

/// 定义处理请求进度的闭包
/// - Parameter progress: 进度上下文，包含请求的进度信息
public typealias ProgressAction = @Sendable (_ progress: ProgressContext<ClientResponse?>) throws -> Void

/// 定义流式数据操作的闭包
/// - Parameters:
///   - request: 客户端请求对象
///   - channel: 用于发送请求的通道
///   - maxChunk: 最大数据块大小
///   - currentIndex: 当前数据块的索引
/// - Returns: 返回要发送的数据块
public typealias StreamingDataAction = @Sendable (_ request: ClientRequest, _ channel: Channel, _ maxChunk: Int, _ currentIndex: Int) async throws -> ByteBuffer

/// 定义异步在发送请求后执行的操作闭包
/// - Parameter channel: 用于发送请求的通道
/// - Returns: 返回一个EventLoopFuture，表示异步操作的结果
public typealias AsyncAfterSendAction =  @Sendable (_ channel: Channel) -> EventLoopFuture<Void>

/// 定义异步流式数据操作的闭包
/// - Parameters:
///   - request: 客户端请求对象
///   - channel: 用于发送请求的通道
///   - maxChunk: 最大数据块大小
///   - currentIndex: 当前数据块的索引
/// - Returns: 返回一个EventLoopFuture，包含要发送的数据块
public typealias AsyncStreamingDataAction = @Sendable (_ request: ClientRequest, _ channel: Channel, _ maxChunk: Int, _ currentIndex: Int) -> EventLoopFuture<ByteBuffer>

/// 客户端协议，定义了与服务器交互的各种方法
public protocol WhooshingClient: Sendable {
    
    // MARK: - 同步请求方法
    func get(_ url: URI, headers: HTTPHeaders, beforeSend: @escaping BeforeSendAction, afterSend: @escaping AfterSendAction, progress: @escaping ProgressAction) async throws -> ClientResponse
    func post(_ url: URI, headers: HTTPHeaders, beforeSend: @escaping BeforeSendAction, afterSend: @escaping AfterSendAction, progress: @escaping ProgressAction) async throws -> ClientResponse
    func patch(_ url: URI, headers: HTTPHeaders, beforeSend: @escaping BeforeSendAction, afterSend: @escaping AfterSendAction, progress: @escaping ProgressAction) async throws -> ClientResponse
    func put(_ url: URI, headers: HTTPHeaders, beforeSend: @escaping BeforeSendAction, afterSend: @escaping AfterSendAction, progress: @escaping ProgressAction) async throws -> ClientResponse
    func delete(_ url: URI, headers: HTTPHeaders, beforeSend: @escaping BeforeSendAction, afterSend: @escaping AfterSendAction, progress: @escaping ProgressAction) async throws -> ClientResponse
    func send(_ method: HTTPMethod, to url: URI, headers: HTTPHeaders, beforeSend: @escaping BeforeSendAction, afterSend: @escaping AfterSendAction, progress: @escaping ProgressAction) async throws -> ClientResponse
    func post<T>(_ url: URI, headers: HTTPHeaders, content: T, afterSend: @escaping AfterSendAction, progress: @escaping ProgressAction) async throws -> ClientResponse where T: Content
    func patch<T>(_ url: URI, headers: HTTPHeaders, content: T, afterSend: @escaping AfterSendAction, progress: @escaping ProgressAction) async throws -> ClientResponse where T: Content
    func put<T>(_ url: URI, headers: HTTPHeaders, content: T, afterSend: @escaping AfterSendAction, progress: @escaping ProgressAction) async throws -> ClientResponse where T: Content

    // MARK: - 同步流式请求方法
    func streamPost(_ url: URI, headers: HTTPHeaders, bodySize: Int, stream: @escaping StreamingDataAction, beforeSend: @escaping BeforeSendAction, afterSend: @escaping AfterSendAction, progress: @escaping ProgressAction) async throws
    func streamPatch(_ url: URI, headers: HTTPHeaders, bodySize: Int, stream: @escaping StreamingDataAction, beforeSend: @escaping BeforeSendAction, afterSend: @escaping AfterSendAction, progress: @escaping ProgressAction) async throws
    func streamPut(_ url: URI, headers: HTTPHeaders, bodySize: Int, stream: @escaping StreamingDataAction, beforeSend: @escaping BeforeSendAction, afterSend: @escaping AfterSendAction, progress: @escaping ProgressAction) async throws
    func streamSend(_ method: HTTPMethod, to url: URI, headers: HTTPHeaders, bodySize: Int, stream: @escaping StreamingDataAction, beforeSend: @escaping BeforeSendAction, afterSend: @escaping AfterSendAction, progress: @escaping ProgressAction) async throws
    
    // MARK: - 同步文件上传方法
    func filePost(_ url: URI, file: String, beforeSend: @escaping BeforeSendAction, afterSend: @escaping AfterSendAction, progress: @escaping ProgressAction) async throws
    func filePatch(_ url: URI, file: String, beforeSend: @escaping BeforeSendAction, afterSend: @escaping AfterSendAction, progress: @escaping ProgressAction) async throws
    func filePut(_ url: URI, file: String, beforeSend: @escaping BeforeSendAction, afterSend: @escaping AfterSendAction, progress: @escaping ProgressAction) async throws
    func fileSend(_ method: HTTPMethod, to url: URI, file: String, beforeSend: @escaping BeforeSendAction, afterSend: @escaping AfterSendAction, progress: @escaping ProgressAction) async throws

    // MARK: - 异步请求方法
    @Sendable func asyncGet(_ url: URI, headers: HTTPHeaders, beforeSend: @escaping BeforeSendAction, afterSend: @escaping AsyncAfterSendAction, progress: @escaping ProgressAction) -> EventLoopFuture<ClientResponse>
    @Sendable func asyncPost(_ url: URI, headers: HTTPHeaders, beforeSend: @escaping BeforeSendAction, afterSend: @escaping AsyncAfterSendAction, progress: @escaping ProgressAction) -> EventLoopFuture<ClientResponse>
    @Sendable func asyncPatch(_ url: URI, headers: HTTPHeaders, beforeSend: @escaping BeforeSendAction, afterSend: @escaping AsyncAfterSendAction, progress: @escaping ProgressAction) -> EventLoopFuture<ClientResponse>
    @Sendable func asyncPut(_ url: URI, headers: HTTPHeaders, beforeSend: @escaping BeforeSendAction, afterSend: @escaping AsyncAfterSendAction, progress: @escaping ProgressAction) -> EventLoopFuture<ClientResponse>
    @Sendable func asyncDelete(_ url: URI, headers: HTTPHeaders, beforeSend: @escaping BeforeSendAction, afterSend: @escaping AsyncAfterSendAction, progress: @escaping ProgressAction) -> EventLoopFuture<ClientResponse>
    @Sendable func asyncSend(_ method: HTTPMethod, to url: URI, headers: HTTPHeaders, beforeSend: @escaping BeforeSendAction, afterSend: @escaping AsyncAfterSendAction, progress: @escaping ProgressAction) -> EventLoopFuture<ClientResponse>
    @Sendable func asyncPost<T>(_ url: URI, headers: HTTPHeaders, content: T, afterSend: @escaping AsyncAfterSendAction, progress: @escaping ProgressAction) -> EventLoopFuture<ClientResponse> where T: Content
    @Sendable func asyncPatch<T>(_ url: URI, headers: HTTPHeaders, content: T, afterSend: @escaping AsyncAfterSendAction, progress: @escaping ProgressAction) -> EventLoopFuture<ClientResponse> where T: Content
    @Sendable func asyncPut<T>(_ url: URI, headers: HTTPHeaders, content: T, afterSend: @escaping AsyncAfterSendAction, progress: @escaping ProgressAction) -> EventLoopFuture<ClientResponse> where T: Content
    
    // MARK: - 异步流式请求方法
    @Sendable func asyncStreamPost(_ url: URI, headers: HTTPHeaders, bodySize: Int, stream: @escaping AsyncStreamingDataAction, beforeSend: @escaping BeforeSendAction, afterSend: @escaping AsyncAfterSendAction, progress: @escaping ProgressAction) -> EventLoopFuture<Void>
    @Sendable func asyncStreamPatch(_ url: URI, headers: HTTPHeaders, bodySize: Int, stream: @escaping AsyncStreamingDataAction, beforeSend: @escaping BeforeSendAction, afterSend: @escaping AsyncAfterSendAction, progress: @escaping ProgressAction) -> EventLoopFuture<Void>
    @Sendable func asyncStreamPut(_ url: URI, headers: HTTPHeaders, bodySize: Int, stream: @escaping AsyncStreamingDataAction, beforeSend: @escaping BeforeSendAction, afterSend: @escaping AsyncAfterSendAction, progress: @escaping ProgressAction) -> EventLoopFuture<Void>
    @Sendable func asyncStreamSend(_ method: HTTPMethod, to url: URI, headers: HTTPHeaders, bodySize: Int, stream: @escaping AsyncStreamingDataAction, beforeSend: @escaping BeforeSendAction, afterSend: @escaping AsyncAfterSendAction, progress: @escaping ProgressAction) -> EventLoopFuture<Void>

    // MARK: - 异步文件上传方法
    @Sendable func asyncFilePost(_ url: URI, file: String, beforeSend: @escaping BeforeSendAction, afterSend: @escaping AsyncAfterSendAction, progress: @escaping ProgressAction) -> EventLoopFuture<Void>
    @Sendable func asyncFilePatch(_ url: URI, file: String, beforeSend: @escaping BeforeSendAction, afterSend: @escaping AsyncAfterSendAction, progress: @escaping ProgressAction) -> EventLoopFuture<Void>
    @Sendable func asyncFilePut(_ url: URI, file: String, beforeSend: @escaping BeforeSendAction, afterSend: @escaping AsyncAfterSendAction, progress: @escaping ProgressAction) -> EventLoopFuture<Void>
    @Sendable func asyncFileSend(_ method: HTTPMethod, to url: URI, file: String, beforeSend: @escaping BeforeSendAction, afterSend: @escaping AsyncAfterSendAction, progress: @escaping ProgressAction) -> EventLoopFuture<Void>

    // MARK: - 核心实现
    
    /// 用于文件操作的EventLoop
    var fileEventLoop: EventLoop { get }
    
    /// 默认的发送后操作实现
    static func defaultAfterSend(channel: Channel) -> EventLoopFuture<Void>

    /// 核心发送方法
    @Sendable func send(
        _ method: HTTPMethod,
        headers: HTTPHeaders,
        to url: URI,
        bufferStrategy: BufferStrategy,
        beforeSend: @escaping BeforeSendAction,
        afterSend: @escaping AsyncAfterSendAction,
        progress: @escaping ProgressAction
    ) -> EventLoopFuture<ClientResponse?>
}

// MARK: - 同步请求默认实现
public extension WhooshingClient {
    /// 发送GET请求（默认参数实现）
    /// - Parameters:
    ///   - url: 目标URI，格式为 `URI`
    ///   - headers: HTTP头字段，默认为空字典
    ///   - beforeSend: 请求发送前的回调闭包，默认不做任何操作
    ///   - afterSend: 请求发送后的回调闭包，默认不做任何操作
    ///   - progress: 进度回调闭包，默认不做任何操作
    /// - Returns: 返回异步的 `ClientResponse`
    /// - Throws: 可能抛出网络错误或编解码错误
    func get(
        _ url: URI,
        headers: HTTPHeaders = [:],
        beforeSend: @escaping BeforeSendAction = { _, _ in },
        afterSend: @escaping AfterSendAction = { _ in },
        progress: @escaping ProgressAction = { _ in }
    ) async throws -> ClientResponse {
        try await send(.GET, to: url, headers: headers, beforeSend: beforeSend, afterSend: afterSend, progress: progress)
    }

    /// 发送POST请求（默认参数实现）
    /// - 参数及返回值同GET方法
    func post(
        _ url: URI,
        headers: HTTPHeaders = [:],
        beforeSend: @escaping BeforeSendAction = { _, _ in },
        afterSend: @escaping AfterSendAction = { _ in },
        progress: @escaping ProgressAction = { _ in }
    ) async throws -> ClientResponse {
        try await send(.POST, to: url, headers: headers, beforeSend: beforeSend, afterSend: afterSend, progress: progress)
    }

    /// 发送PATCH请求（默认参数实现）
    /// - 参数及返回值同GET方法
    func patch(
        _ url: URI,
        headers: HTTPHeaders = [:],
        beforeSend: @escaping BeforeSendAction = { _, _ in },
        afterSend: @escaping AfterSendAction = { _ in },
        progress: @escaping ProgressAction = { _ in }
    ) async throws -> ClientResponse {
        try await send(.PATCH, to: url, headers: headers, beforeSend: beforeSend, afterSend: afterSend, progress: progress)
    }

    /// 发送PUT请求（默认参数实现）
    /// - 参数及返回值同GET方法
    func put(
        _ url: URI,
        headers: HTTPHeaders = [:],
        beforeSend: @escaping BeforeSendAction = { _, _ in },
        afterSend: @escaping AfterSendAction = { _ in },
        progress: @escaping ProgressAction = { _ in }
    ) async throws -> ClientResponse {
        try await send(.PUT, to: url, headers: headers, beforeSend: beforeSend, afterSend: afterSend, progress: progress)
    }

    /// 发送DELETE请求（默认参数实现）
    /// - 参数及返回值同GET方法
    func delete(
        _ url: URI,
        headers: HTTPHeaders = [:],
        beforeSend: @escaping BeforeSendAction = { _, _ in },
        afterSend: @escaping AfterSendAction = { _ in },
        progress: @escaping ProgressAction = { _ in }
    ) async throws -> ClientResponse {
        try await send(.DELETE, to: url, headers: headers, beforeSend: beforeSend, afterSend: afterSend, progress: progress)
    }

    /// 通用请求发送方法（默认参数实现）
    /// - Parameters:
    ///   - method: HTTP方法（GET/POST等）
    ///   - 其他参数同GET方法
    /// - 实现说明：
    ///   1. 将异步回调转换为EventLoopFuture
    ///   2. 调用底层异步发送方法
    ///   3. 通过get()同步等待结果
    func send(
        _ method: HTTPMethod,
        to url: URI,
        headers: HTTPHeaders = [:],
        beforeSend: @escaping BeforeSendAction = { _, _ in },
        afterSend: @escaping AfterSendAction = { _ in },
        progress: @escaping ProgressAction = { _ in }
    ) async throws -> ClientResponse {
        try await asyncSend(
            method,
            to: url,
            headers: headers,
            beforeSend: beforeSend,
            afterSend: { b in
                b.eventLoop.makeFutureWithTask {
                    try await afterSend(b)
                }
            },
            progress: progress
        ).get()
    }
}

// MARK: - 同步内容编码请求默认实现
public extension WhooshingClient {
    /// 发送带内容的POST请求（默认参数实现）
    /// - Parameters:
    ///   - url: 目标URI，格式为 `URI`
    ///   - headers: HTTP头字段，默认为空字典
    ///   - content: 遵循Content协议的可编码内容
    ///   - afterSend: 请求发送后的回调闭包，默认不做任何操作
    ///   - progress: 进度回调闭包，默认不做任何操作
    /// - Returns: 服务器响应结果
    /// - Throws: 可能抛出编码错误或网络错误
    /// - 实现流程：
    ///   1. 通过reflect方法将同步回调转换为异步回调
    ///   2. 调用底层asyncPost方法
    ///   3. 在beforeSend闭包中自动执行内容编码
    ///   4. 等待并返回最终响应结果
    /// - 注意事项：
    ///   - 类型参数T必须遵循Content协议
    ///   - 内容编码使用Vapor的默认编码器
    ///   - 进度回调包含请求头和内容的编码进度
    func post<T>(
        _ url: URI,
        headers: HTTPHeaders = [:],
        content: T,
        afterSend: @escaping AfterSendAction = { _ in },
        progress: @escaping ProgressAction = { _ in }
    ) async throws -> ClientResponse where T: Content {
        try await reflect(url, headers, content, afterSend, progress, to: asyncPost)
    }

    /// 发送带内容的PATCH请求（默认参数实现）
    /// - Parameters:
    ///   - url: 目标URI，格式为 `URI`
    ///   - headers: HTTP头字段，默认为空字典
    ///   - content: 遵循Content协议的可编码内容
    ///   - afterSend: 请求发送后的回调闭包，默认不做任何操作
    ///   - progress: 进度回调闭包，默认不做任何操作
    /// - Returns: 服务器响应结果
    /// - Throws: 可能抛出编码错误或网络错误
    /// - 实现流程：
    ///   1. 通过reflect方法将同步回调转换为异步回调
    ///   2. 调用底层asyncPatch方法
    ///   3. 在beforeSend闭包中自动执行内容编码
    ///   4. 等待并返回最终响应结果
    /// - 典型使用场景：
    ///   - 部分更新资源内容
    /// - 注意事项：
    ///   - 与POST请求的区别在于语义而非实现
    func patch<T>(
        _ url: URI,
        headers: HTTPHeaders = [:],
        content: T,
        afterSend: @escaping AfterSendAction = { _ in },
        progress: @escaping ProgressAction = { _ in }
    ) async throws -> ClientResponse where T: Content {
        try await reflect(url, headers, content, afterSend, progress, to: asyncPatch)
    }

    /// 发送带内容的PUT请求（默认参数实现）
    /// - Parameters:
    ///   - url: 目标URI，格式为 `URI`
    ///   - headers: HTTP头字段，默认为空字典
    ///   - content: 遵循Content协议的可编码内容
    ///   - afterSend: 请求发送后的回调闭包，默认不做任何操作
    ///   - progress: 进度回调闭包，默认不做任何操作
    /// - Returns: 服务器响应结果
    /// - Throws: 可能抛出编码错误或网络错误
    /// - 实现流程：
    ///   1. 通过reflect方法将同步回调转换为异步回调
    ///   2. 调用底层asyncPut方法
    ///   3. 在beforeSend闭包中自动执行内容编码
    ///   4. 等待并返回最终响应结果
    /// - 典型使用场景：
    ///   - 完全替换资源内容
    /// - 注意事项：
    ///   - 与POST请求的区别在于语义（幂等性）
    func put<T>(
        _ url: URI,
        headers: HTTPHeaders = [:],
        content: T,
        afterSend: @escaping AfterSendAction = { _ in },
        progress: @escaping ProgressAction = { _ in }
    ) async throws -> ClientResponse where T: Content {
        try await reflect(url, headers, content, afterSend, progress, to: asyncPut)
    }

    private func reflect<T>(
        _ url: URI,
        _ headers: HTTPHeaders,
        _ content: T,
        _ afterSend: @escaping AfterSendAction,
        _ progress: @escaping ProgressAction,
        to: (URI, HTTPHeaders, T, @escaping AsyncAfterSendAction, @escaping ProgressAction) -> EventLoopFuture<ClientResponse>
    ) async throws -> ClientResponse where T: Content {
        try await to(url, headers, content, { b in b.eventLoop.makeFutureWithTask { try await afterSend(b) } }, progress).get()
    }
}

// MARK: - 同步流式请求默认实现
public extension WhooshingClient {
    /// 流式POST请求（默认参数实现）
    /// - Parameters:
    ///   - url: 目标URI，格式为 `URI`
    ///   - headers: HTTP头字段，默认为空字典
    ///   - bodySize: 请求体总大小（字节），用于进度计算
    ///   - stream: 数据流生成闭包，返回ByteBuffer
    ///   - beforeSend: 请求发送前的回调闭包，默认不做任何操作
    ///   - afterSend: 请求发送后的回调闭包，默认不做任何操作
    ///   - progress: 进度回调闭包，默认不做任何操作
    /// - Throws: 可能抛出网络错误或流生成错误
    /// - 实现流程：
    ///   1. 调用通用流式发送方法streamSend
    ///   2. 设置HTTP方法为.POST
    ///   3. 使用提供的流式数据生成闭包
    /// - 注意事项：
    ///   - bodySize必须与实际数据大小一致
    ///   - stream闭包可能被多次调用
    ///   - 适用于大文件或大数据流传输
    func streamPost(
        _ url: URI,
        headers: HTTPHeaders = [:],
        bodySize: Int,
        stream: @escaping StreamingDataAction,
        beforeSend: @escaping BeforeSendAction = { _, _ in },
        afterSend: @escaping AfterSendAction = { _ in },
        progress: @escaping ProgressAction = { _ in }
    ) async throws {
        try await streamSend(.POST, to: url, headers: headers, bodySize: bodySize, stream: stream, beforeSend: beforeSend, afterSend: afterSend, progress: progress)
    }

    /// 流式PATCH请求（默认参数实现）
    /// - Parameters:
    ///   - url: 目标URI，格式为 `URI`
    ///   - headers: HTTP头字段，默认为空字典
    ///   - bodySize: 请求体总大小（字节），用于进度计算
    ///   - stream: 数据流生成闭包，返回ByteBuffer
    ///   - beforeSend: 请求发送前的回调闭包，默认不做任何操作
    ///   - afterSend: 请求发送后的回调闭包，默认不做任何操作
    ///   - progress: 进度回调闭包，默认不做任何操作
    /// - Throws: 可能抛出网络错误或流生成错误
    /// - 实现流程：
    ///   1. 调用通用流式发送方法streamSend
    ///   2. 设置HTTP方法为.PATCH
    ///   3. 使用提供的流式数据生成闭包
    /// - 典型使用场景：
    ///   - 部分更新大尺寸资源
    func streamPatch(
        _ url: URI,
        headers: HTTPHeaders = [:],
        bodySize: Int,
        stream: @escaping StreamingDataAction,
        beforeSend: @escaping BeforeSendAction = { _, _ in },
        afterSend: @escaping AfterSendAction = { _ in },
        progress: @escaping ProgressAction = { _ in }
    ) async throws {
        try await streamSend(.PATCH, to: url, headers: headers, bodySize: bodySize, stream: stream, beforeSend: beforeSend, afterSend: afterSend, progress: progress)
    }

    /// 流式PUT请求（默认参数实现）
    /// - Parameters:
    ///   - url: 目标URI，格式为 `URI`
    ///   - headers: HTTP头字段，默认为空字典
    ///   - bodySize: 请求体总大小（字节），用于进度计算
    ///   - stream: 数据流生成闭包，返回ByteBuffer
    ///   - beforeSend: 请求发送前的回调闭包，默认不做任何操作
    ///   - afterSend: 请求发送后的回调闭包，默认不做任何操作
    ///   - progress: 进度回调闭包，默认不做任何操作
    /// - Throws: 可能抛出网络错误或流生成错误
    /// - 实现流程：
    ///   1. 调用通用流式发送方法streamSend
    ///   2. 设置HTTP方法为.PUT
    ///   3. 使用提供的流式数据生成闭包
    /// - 典型使用场景：
    ///   - 完全替换大尺寸资源
    func streamPut(
        _ url: URI,
        headers: HTTPHeaders = [:],
        bodySize: Int,
        stream: @escaping StreamingDataAction,
        beforeSend: @escaping BeforeSendAction = { _, _ in },
        afterSend: @escaping AfterSendAction = { _ in },
        progress: @escaping ProgressAction = { _ in }
    ) async throws {
        try await streamSend(.PUT, to: url, headers: headers, bodySize: bodySize, stream: stream, beforeSend: beforeSend, afterSend: afterSend, progress: progress)
    }

    /// 通用流式请求方法（默认参数实现）
    /// - Parameters:
    ///   - method: HTTP方法（GET/POST/PUT/PATCH/DELETE等）
    ///   - url: 目标URI，格式为 `URI`
    ///   - headers: HTTP头字段，默认为空字典
    ///   - bodySize: 请求体总大小（字节）
    ///   - stream: 数据流生成闭包
    ///   - beforeSend: 请求发送前的回调闭包
    ///   - afterSend: 请求发送后的回调闭包
    ///   - progress: 进度回调闭包
    /// - Throws: 可能抛出网络错误或流生成错误
    /// - 实现流程：
    ///   1. 将异步闭包转换为EventLoopFuture形式
    ///   2. 调用底层asyncStreamSend方法
    ///   3. 通过get()同步等待结果
    /// - 注意事项：
    ///   - 内部使用eventLoop.makeFutureWithTask进行异步转同步
    ///   - 流式传输不支持获取具体响应内容
    func streamSend(
        _ method: HTTPMethod,
        to url: URI,
        headers: HTTPHeaders = [:],
        bodySize: Int,
        stream: @escaping StreamingDataAction,
        beforeSend: @escaping BeforeSendAction = { _, _ in },
        afterSend: @escaping AfterSendAction = { _ in },
        progress: @escaping ProgressAction = { _ in }
    ) async throws {
        try await asyncStreamSend(
            method,
            to: url,
            headers: headers,
            bodySize: bodySize,
            stream: { request, channel, maxChunk, currentIndex in
                // 将异步stream闭包转换为EventLoopFuture
                channel.eventLoop.makeFutureWithTask {
                    try await stream(request, channel, maxChunk, currentIndex)
                }
            },
            beforeSend: beforeSend,
            afterSend: { channel in
                // 将异步afterSend闭包转换为EventLoopFuture
                channel.eventLoop.makeFutureWithTask {
                    try await afterSend(channel)
                }
            },
            progress: progress
        ).get() // 等待异步操作完成
    }
}

// MARK: - 同步文件操作默认实现
public extension WhooshingClient {
    /// 文件上传POST请求（默认参数实现）
    /// - Parameters:
    ///   - url: 目标URI，格式为 `URI`
    ///   - file: 本地文件路径字符串
    ///   - beforeSend: 请求发送前的回调闭包，默认不做任何操作
    ///   - afterSend: 请求发送后的回调闭包，默认不做任何操作
    ///   - progress: 进度回调闭包，默认不做任何操作
    /// - Throws: 可能抛出文件操作错误或网络错误
    /// - 实现流程：
    ///   1. 调用通用文件上传方法fileSend
    ///   2. 设置HTTP方法为.POST
    ///   3. 使用提供的回调闭包
    /// - 注意事项：
    ///   - 文件路径必须是有效的本地文件路径
    ///   - 自动添加Content-Disposition头
    func filePost(
        _ url: URI,
        file: String,
        beforeSend: @escaping BeforeSendAction = { _, _ in },
        afterSend: @escaping AfterSendAction = { _ in },
        progress: @escaping ProgressAction = { _ in }
    ) async throws {
        try await fileSend(
            .POST,
            to: url,
            file: file,
            beforeSend: beforeSend,
            afterSend: afterSend,
            progress: progress
        )
    }

    /// 文件上传PATCH请求（默认参数实现）
    /// - Parameters:
    ///   - url: 目标URI，格式为 `URI`
    ///   - file: 本地文件路径字符串
    ///   - beforeSend: 请求发送前的回调闭包，默认不做任何操作
    ///   - afterSend: 请求发送后的回调闭包，默认不做任何操作
    ///   - progress: 进度回调闭包，默认不做任何操作
    /// - Throws: 可能抛出文件操作错误或网络错误
    /// - 实现流程：
    ///   1. 调用通用文件上传方法fileSend
    ///   2. 设置HTTP方法为.PATCH
    ///   3. 使用提供的回调闭包
    /// - 典型使用场景：
    ///   - 部分更新服务器文件
    func filePatch(
        _ url: URI,
        file: String,
        beforeSend: @escaping BeforeSendAction = { _, _ in },
        afterSend: @escaping AfterSendAction = { _ in },
        progress: @escaping ProgressAction = { _ in }
    ) async throws {
        try await fileSend(
            .PATCH,
            to: url,
            file: file,
            beforeSend: beforeSend,
            afterSend: afterSend,
            progress: progress
        )
    }

    /// 文件上传PUT请求（默认参数实现）
    /// - Parameters:
    ///   - url: 目标URI，格式为 `URI`
    ///   - file: 本地文件路径字符串
    ///   - beforeSend: 请求发送前的回调闭包，默认不做任何操作
    ///   - afterSend: 请求发送后的回调闭包，默认不做任何操作
    ///   - progress: 进度回调闭包，默认不做任何操作
    /// - Throws: 可能抛出文件操作错误或网络错误
    /// - 实现流程：
    ///   1. 调用通用文件上传方法fileSend
    ///   2. 设置HTTP方法为.PUT
    ///   3. 使用提供的回调闭包
    /// - 典型使用场景：
    ///   - 完全替换服务器文件
    func filePut(
        _ url: URI,
        file: String,
        beforeSend: @escaping BeforeSendAction = { _, _ in },
        afterSend: @escaping AfterSendAction = { _ in },
        progress: @escaping ProgressAction = { _ in }
    ) async throws {
        try await fileSend(
            .PUT,
            to: url,
            file: file,
            beforeSend: beforeSend,
            afterSend: afterSend,
            progress: progress
        )
    }

    /// 通用文件上传方法（默认参数实现）
    /// - Parameters:
    ///   - method: HTTP方法（POST/PUT/PATCH）
    ///   - url: 目标URI，格式为 `URI`
    ///   - file: 本地文件路径字符串
    ///   - beforeSend: 请求发送前的回调闭包
    ///   - afterSend: 请求发送后的回调闭包
    ///   - progress: 进度回调闭包
    /// - Throws: 可能抛出文件操作错误或网络错误
    /// - 实现流程：
    ///   1. 将异步回调转换为EventLoopFuture形式
    ///   2. 调用底层asyncFileSend方法
    ///   3. 通过get()同步等待结果
    /// - 注意事项：
    ///   - 内部使用eventLoop.makeFutureWithTask进行异步转同步
    ///   - 文件操作在专用fileEventLoop中执行
    func fileSend(
        _ method: HTTPMethod,
        to url: URI,
        file: String,
        beforeSend: @escaping BeforeSendAction = { _, _ in },
        afterSend: @escaping AfterSendAction = { _ in },
        progress: @escaping ProgressAction = { _ in }
    ) async throws {
        try await asyncFileSend(
            method,
            to: url,
            file: file,
            beforeSend: beforeSend,
            afterSend: { channel in
                // 将异步afterSend闭包转换为EventLoopFuture
                channel.eventLoop.makeFutureWithTask {
                    try await afterSend(channel)
                }
            },
            progress: progress
        ).get() // 等待异步操作完成
    }
}

// MARK: - 异步请求默认实现
public extension WhooshingClient {
    /// 默认的发送后操作实现
    /// - Parameter channel: 请求通道对象
    /// - Returns: 返回成功的EventLoopFuture
    /// - 说明: 提供空的默认实现，仅返回channel的已成功Future
    static func defaultAfterSend(channel: Channel) -> EventLoopFuture<Void> {
        channel.eventLoop.makeSucceededFuture(())
    }

    /// 异步GET请求（默认参数实现）
    /// - Parameters:
    ///   - url: 目标URI
    ///   - headers: HTTP头字段，默认为空字典
    ///   - beforeSend: 请求前回调，默认为空操作
    ///   - afterSend: 请求后回调，默认为defaultAfterSend
    ///   - progress: 进度回调，默认为空操作
    /// - Returns: 包含响应结果的EventLoopFuture
    @Sendable func asyncGet(
        _ url: URI,
        headers: HTTPHeaders = [:],
        beforeSend: @escaping BeforeSendAction = { _, _ in },
        afterSend: @escaping AsyncAfterSendAction = defaultAfterSend,
        progress: @escaping ProgressAction = { _ in }
    ) -> EventLoopFuture<ClientResponse> {
        self.asyncSend(.GET, to: url, headers: headers, beforeSend: beforeSend, afterSend: afterSend, progress: progress)
    }

    /// 异步POST请求（默认参数实现）
    /// - Parameters:
    ///   - url: 目标URI，格式为 `URI`
    ///   - headers: HTTP头字段，默认为空字典
    ///   - beforeSend: 请求发送前的回调闭包，默认不做任何操作
    ///   - afterSend: 请求发送后的回调闭包，默认为defaultAfterSend
    ///   - progress: 进度回调闭包，默认不做任何操作
    /// - Returns: 包含响应结果的EventLoopFuture
    /// - 实现说明：调用通用异步请求方法asyncSend，设置HTTP方法为.POST
    @Sendable func asyncPost(
        _ url: URI,
        headers: HTTPHeaders = [:],
        beforeSend: @escaping BeforeSendAction = { _, _ in },
        afterSend: @escaping AsyncAfterSendAction = defaultAfterSend,
        progress: @escaping ProgressAction = { _ in }
    ) -> EventLoopFuture<ClientResponse> {
        return self.asyncSend(
            .POST,
            to: url,
            headers: headers,
            beforeSend: beforeSend,
            afterSend: afterSend,
            progress: progress
        )
    }

    /// 异步PATCH请求（默认参数实现）
    /// - Parameters:
    ///   - url: 目标URI，格式为 `URI`
    ///   - headers: HTTP头字段，默认为空字典
    ///   - beforeSend: 请求发送前的回调闭包，默认不做任何操作
    ///   - afterSend: 请求发送后的回调闭包，默认为defaultAfterSend
    ///   - progress: 进度回调闭包，默认不做任何操作
    /// - Returns: 包含响应结果的EventLoopFuture
    /// - 实现说明：调用通用异步请求方法asyncSend，设置HTTP方法为.PATCH
    @Sendable func asyncPatch(
        _ url: URI,
        headers: HTTPHeaders = [:],
        beforeSend: @escaping BeforeSendAction = { _, _ in },
        afterSend: @escaping AsyncAfterSendAction = defaultAfterSend,
        progress: @escaping ProgressAction = { _ in }
    ) -> EventLoopFuture<ClientResponse> {
        return self.asyncSend(.PATCH, to: url, headers: headers, beforeSend: beforeSend, afterSend: afterSend, progress: progress)
    }

    /// 异步PUT请求（默认参数实现）
    /// - Parameters:
    ///   - url: 目标URI，格式为 `URI`
    ///   - headers: HTTP头字段，默认为空字典
    ///   - beforeSend: 请求发送前的回调闭包，默认不做任何操作
    ///   - afterSend: 请求发送后的回调闭包，默认为defaultAfterSend
    ///   - progress: 进度回调闭包，默认不做任何操作
    /// - Returns: 包含响应结果的EventLoopFuture
    /// - 实现说明：调用通用异步请求方法asyncSend，设置HTTP方法为.PUT
    @Sendable func asyncPut(
        _ url: URI,
        headers: HTTPHeaders = [:],
        beforeSend: @escaping BeforeSendAction = { _, _ in },
        afterSend: @escaping AsyncAfterSendAction = defaultAfterSend,
        progress: @escaping ProgressAction = { _ in }
    ) -> EventLoopFuture<ClientResponse> {
        return self.asyncSend(.PUT, to: url, headers: headers, beforeSend: beforeSend, afterSend: afterSend, progress: progress)
    }

    /// 异步DELETE请求（默认参数实现）
    /// - Parameters:
    ///   - url: 目标URI，格式为 `URI`
    ///   - headers: HTTP头字段，默认为空字典
    ///   - beforeSend: 请求发送前的回调闭包，默认不做任何操作
    ///   - afterSend: 请求发送后的回调闭包，默认为defaultAfterSend
    ///   - progress: 进度回调闭包，默认不做任何操作
    /// - Returns: 包含响应结果的EventLoopFuture
    /// - 实现说明：调用通用异步请求方法asyncSend，设置HTTP方法为.DELETE
    @Sendable func asyncDelete(
        _ url: URI,
        headers: HTTPHeaders = [:],
        beforeSend: @escaping BeforeSendAction = { _, _ in },
        afterSend: @escaping AsyncAfterSendAction = defaultAfterSend,
        progress: @escaping ProgressAction = { _ in }
    ) -> EventLoopFuture<ClientResponse> {
        return self.asyncSend(.DELETE, to: url, headers: headers, beforeSend: beforeSend, afterSend: afterSend, progress: progress)
    }
    
    /// 通用异步请求方法（默认参数实现）
    /// - 实现说明：
    ///   1. 设置缓冲区策略为.collect（完整收集响应）
    ///   2. 调用核心send方法
    ///   3. 解包可选响应（map { $0! }）
    @Sendable func asyncSend(
        _ method: HTTPMethod,
        to url: URI,
        headers: HTTPHeaders = [:],
        beforeSend: @escaping BeforeSendAction = { _, _ in },
        afterSend: @escaping AsyncAfterSendAction = defaultAfterSend,
        progress: @escaping ProgressAction = { _ in }
    ) -> EventLoopFuture<ClientResponse> {
        self.send(method, headers: headers, to: url, bufferStrategy: .collect, beforeSend: beforeSend, afterSend: afterSend, progress: progress).map { $0! } // 强制解包因为.collect策略保证必有响应
    }
}

// MARK: - 异步内容编码默认实现
public extension WhooshingClient {
    /// 异步发送带内容的POST请求（默认参数实现）
    /// - Parameters:
    ///   - url: 目标URI，格式为 `URI`
    ///   - headers: HTTP头字段，默认为空字典
    ///   - content: 遵循Content协议的可编码内容
    ///   - afterSend: 请求发送后的回调闭包，默认为defaultAfterSend
    ///   - progress: 进度回调闭包，默认不做任何操作
    /// - Returns: 包含响应结果的EventLoopFuture
    /// - 实现机制：
    ///   1. 在beforeSend闭包中自动执行内容编码
    ///   2. 调用基础异步POST方法发送请求
    /// - 注意事项：
    ///   - 类型参数T必须遵循Content协议
    @Sendable func asyncPost<T>(
        _ url: URI,
        headers: HTTPHeaders = [:],
        content: T,
        afterSend: @escaping AsyncAfterSendAction = defaultAfterSend,
        progress: @escaping ProgressAction = { _ in }
    ) -> EventLoopFuture<ClientResponse> where T: Content {
        self.asyncPost(url, headers: headers, beforeSend: { req, _ in try req.content.encode(content) }, afterSend: afterSend, progress: progress)
    }

    /// 异步发送带内容的PATCH请求（默认参数实现）
    /// - Parameters:
    ///   - url: 目标URI，格式为 `URI`
    ///   - headers: HTTP头字段，默认为空字典
    ///   - content: 遵循Content协议的可编码内容
    ///   - afterSend: 请求发送后的回调闭包，默认为defaultAfterSend
    ///   - progress: 进度回调闭包，默认不做任何操作
    /// - Returns: 包含响应结果的EventLoopFuture
    /// - 实现机制：
    ///   1. 在beforeSend闭包中自动执行内容编码
    ///   2. 调用基础异步PATCH方法发送请求
    @Sendable func asyncPatch<T>(
        _ url: URI,
        headers: HTTPHeaders = [:],
        content: T,
        afterSend: @escaping AsyncAfterSendAction = defaultAfterSend,
        progress: @escaping ProgressAction = { _ in }
    ) -> EventLoopFuture<ClientResponse> where T: Content {
        return self.asyncPatch(url, headers: headers, beforeSend: { req, _ in try req.content.encode(content) }, afterSend: afterSend, progress: progress)
    }

    /// 异步发送带内容的PUT请求（默认参数实现）
    /// - Parameters:
    ///   - url: 目标URI，格式为 `URI`
    ///   - headers: HTTP头字段，默认为空字典
    ///   - content: 遵循Content协议的可编码内容
    ///   - afterSend: 请求发送后的回调闭包，默认为defaultAfterSend
    ///   - progress: 进度回调闭包，默认不做任何操作
    /// - Returns: 包含响应结果的EventLoopFuture
    /// - 实现机制：
    ///   1. 在beforeSend闭包中自动执行内容编码
    ///   2. 调用基础异步PUT方法发送请求
    @Sendable func asyncPut<T>(
        _ url: URI,
        headers: HTTPHeaders = [:],
        content: T,
        afterSend: @escaping AsyncAfterSendAction = defaultAfterSend,
        progress: @escaping ProgressAction = { _ in }
    ) -> EventLoopFuture<ClientResponse> where T: Content {
        return self.asyncPut(url, headers: headers, beforeSend: { req, _ in try req.content.encode(content) }, afterSend: afterSend, progress: progress)
    }
}

// MARK: - 异步流式请求默认实现
public extension WhooshingClient {
    /// 异步流式POST请求（默认参数实现）
    /// - Parameters:
    ///   - url: 目标URI，格式为 `URI`
    ///   - headers: HTTP头字段，默认为空字典
    ///   - bodySize: 请求体总大小（字节），用于进度计算
    ///   - stream: 异步流式数据生成闭包，返回EventLoopFuture<ByteBuffer>
    ///   - beforeSend: 请求发送前的回调闭包，默认不做任何操作
    ///   - afterSend: 请求发送后的回调闭包，默认为defaultAfterSend
    ///   - progress: 进度回调闭包，默认不做任何操作
    /// - Returns: 表示流式传输完成的EventLoopFuture<Void>
    /// - 实现机制：
    ///   1. 调用通用异步流式发送方法asyncStreamSend
    ///   2. 设置HTTP方法为.POST
    ///   3. 使用提供的流式数据生成闭包
    /// - 注意事项：
    ///   - bodySize必须与实际数据大小一致
    ///   - stream闭包可能被多次调用
    @Sendable func asyncStreamPost(
        _ url: URI,
        headers: HTTPHeaders = [:],
        bodySize: Int,
        stream: @escaping AsyncStreamingDataAction,
        beforeSend: @escaping BeforeSendAction = { _, _ in },
        afterSend: @escaping AsyncAfterSendAction = defaultAfterSend,
        progress: @escaping ProgressAction = { _ in }
    ) -> EventLoopFuture<Void> {
        self.asyncStreamSend(.POST, to: url, headers: headers, bodySize: bodySize, stream: stream, beforeSend: beforeSend, afterSend: afterSend, progress: progress)
    }

    /// 异步流式PATCH请求（默认参数实现）
    /// - Parameters:
    ///   - url: 目标URI，格式为 `URI`
    ///   - headers: HTTP头字段，默认为空字典
    ///   - bodySize: 请求体总大小（字节），用于进度计算
    ///   - stream: 异步流式数据生成闭包，返回EventLoopFuture<ByteBuffer>
    ///   - beforeSend: 请求发送前的回调闭包，默认不做任何操作
    ///   - afterSend: 请求发送后的回调闭包，默认为defaultAfterSend
    ///   - progress: 进度回调闭包，默认不做任何操作
    /// - Returns: 表示流式传输完成的EventLoopFuture<Void>
    /// - 实现机制：
    ///   1. 调用通用异步流式发送方法asyncStreamSend
    ///   2. 设置HTTP方法为.PATCH
    ///   3. 使用提供的流式数据生成闭包
    /// - 典型使用场景：
    ///   - 部分更新大尺寸资源
    @Sendable func asyncStreamPatch(
        _ url: URI,
        headers: HTTPHeaders = [:],
        bodySize: Int,
        stream: @escaping AsyncStreamingDataAction,
        beforeSend: @escaping BeforeSendAction = { _, _ in },
        afterSend: @escaping AsyncAfterSendAction = defaultAfterSend,
        progress: @escaping ProgressAction = { _ in }
    ) -> EventLoopFuture<Void> {
        self.asyncStreamSend(.PATCH, to: url, headers: headers, bodySize: bodySize, stream: stream, beforeSend: beforeSend, afterSend: afterSend, progress: progress)
    }

    /// 异步流式PUT请求（默认参数实现）
    /// - Parameters:
    ///   - url: 目标URI，格式为 `URI`
    ///   - headers: HTTP头字段，默认为空字典
    ///   - bodySize: 请求体总大小（字节），用于进度计算
    ///   - stream: 异步流式数据生成闭包，返回EventLoopFuture<ByteBuffer>
    ///   - beforeSend: 请求发送前的回调闭包，默认不做任何操作
    ///   - afterSend: 请求发送后的回调闭包，默认为defaultAfterSend
    ///   - progress: 进度回调闭包，默认不做任何操作
    /// - Returns: 表示流式传输完成的EventLoopFuture<Void>
    /// - 实现机制：
    ///   1. 调用通用异步流式发送方法asyncStreamSend
    ///   2. 设置HTTP方法为.PUT
    ///   3. 使用提供的流式数据生成闭包
    /// - 典型使用场景：
    ///   - 替换大尺寸资源
    @Sendable func asyncStreamPut(
        _ url: URI,
        headers: HTTPHeaders = [:],
        bodySize: Int,
        stream: @escaping AsyncStreamingDataAction,
        beforeSend: @escaping BeforeSendAction = { _, _ in },
        afterSend: @escaping AsyncAfterSendAction = defaultAfterSend,
        progress: @escaping ProgressAction = { _ in }
    ) -> EventLoopFuture<Void> {
        self.asyncStreamSend(.PUT, to: url, headers: headers, bodySize: bodySize, stream: stream, beforeSend: beforeSend, afterSend: afterSend, progress: progress )
    }

    /// 通用异步流式请求方法（默认参数实现）
    /// - Parameters:
    ///   - method: HTTP方法（GET/POST/PUT/PATCH/DELETE等）
    ///   - url: 目标URI，格式为 `URI`
    ///   - headers: HTTP头字段，默认为空字典
    ///   - bodySize: 请求体总大小（字节）
    ///   - stream: 异步流式数据生成闭包
    ///   - beforeSend: 请求发送前的回调闭包
    ///   - afterSend: 请求发送后的回调闭包
    ///   - progress: 进度回调闭包
    /// - Returns: 表示流式传输完成的EventLoopFuture<Void>
    /// - 实现机制：
    ///   1. 设置缓冲区策略为.streaming
    ///   2. 将bodySize和stream闭包关联到缓冲区策略
    ///   3. 调用核心send方法
    ///   4. 将结果转换为Void（忽略具体响应内容）
    /// - 注意事项：
    ///   - 流式传输过程中可能多次调用stream闭包
    ///   - 进度回调基于bodySize计算
    @Sendable func asyncStreamSend(
        _ method: HTTPMethod,
        to url: URI,
        headers: HTTPHeaders = [:],
        bodySize: Int,
        stream: @escaping AsyncStreamingDataAction,
        beforeSend: @escaping BeforeSendAction = { _, _ in },
        afterSend: @escaping AsyncAfterSendAction = defaultAfterSend,
        progress: @escaping ProgressAction = { _ in }
    ) -> EventLoopFuture<Void> {
        self.send(method, headers: headers, to: url, bufferStrategy: .streaming(totalSize: bodySize, stream: stream), beforeSend: beforeSend, afterSend: afterSend, progress: progress).map { _ in }
    }
}

// MARK: - 异步文件上传默认实现
public extension WhooshingClient {
    /// 异步文件POST上传（默认参数实现）
    /// - Parameters:
    ///   - url: 目标URI，格式为 `URI`
    ///   - file: 本地文件路径字符串
    ///   - beforeSend: 请求发送前的回调闭包，默认不做任何操作
    ///   - afterSend: 请求发送后的回调闭包，默认为defaultAfterSend
    ///   - progress: 进度回调闭包，默认不做任何操作
    /// - Returns: 表示上传操作完成的EventLoopFuture<Void>
    /// - 实现机制：
    ///   1. 调用通用异步文件上传方法asyncFileSend
    ///   2. 设置HTTP方法为.POST
    ///   3. 使用提供的回调闭包
    /// - 注意事项：
    ///   - 文件路径必须是有效的本地文件路径
    ///   - 实际文件操作在fileEventLoop中执行
    ///   - 进度回调会在文件上传过程中触发
    @Sendable func asyncFilePost(
        _ url: URI,
        file: String,
        beforeSend: @escaping BeforeSendAction = { _, _ in },
        afterSend: @escaping AsyncAfterSendAction = defaultAfterSend,
        progress: @escaping ProgressAction = { _ in }
    ) -> EventLoopFuture<Void> {
        self.asyncFileSend(.POST, to: url, file: file, beforeSend: beforeSend, afterSend: afterSend, progress: progress)
    }

    /// 异步文件PATCH上传（默认参数实现）
    /// - Parameters:
    ///   - url: 目标URI，格式为 `URI`
    ///   - file: 本地文件路径字符串
    ///   - beforeSend: 请求发送前的回调闭包，默认不做任何操作
    ///   - afterSend: 请求发送后的回调闭包，默认为defaultAfterSend
    ///   - progress: 进度回调闭包，默认不做任何操作
    /// - Returns: 表示上传操作完成的EventLoopFuture<Void>
    /// - 实现机制：
    ///   1. 调用通用异步文件上传方法asyncFileSend
    ///   2. 设置HTTP方法为.PATCH
    ///   3. 使用提供的回调闭包
    /// - 典型使用场景：
    ///   - 部分更新服务器上的文件资源
    @Sendable func asyncFilePatch(
        _ url: URI,
        file: String,
        beforeSend: @escaping BeforeSendAction = { _, _ in },
        afterSend: @escaping AsyncAfterSendAction = defaultAfterSend,
        progress: @escaping ProgressAction = { _ in }
    ) -> EventLoopFuture<Void> {
        self.asyncFileSend(.PATCH, to: url, file: file, beforeSend: beforeSend, afterSend: afterSend, progress: progress)
    }

    /// 异步文件PUT上传（默认参数实现）
    /// - Parameters:
    ///   - url: 目标URI，格式为 `URI`
    ///   - file: 本地文件路径字符串
    ///   - beforeSend: 请求发送前的回调闭包，默认不做任何操作
    ///   - afterSend: 请求发送后的回调闭包，默认为defaultAfterSend
    ///   - progress: 进度回调闭包，默认不做任何操作
    /// - Returns: 表示上传操作完成的EventLoopFuture<Void>
    /// - 实现机制：
    ///   1. 调用通用异步文件上传方法asyncFileSend
    ///   2. 设置HTTP方法为.PUT
    ///   3. 使用提供的回调闭包
    /// - 典型使用场景：
    ///   - 完整替换服务器上的文件资源
    @Sendable func asyncFilePut(
        _ url: URI,
        file: String,
        beforeSend: @escaping BeforeSendAction = { _, _ in },
        afterSend: @escaping AsyncAfterSendAction = defaultAfterSend,
        progress: @escaping ProgressAction = { _ in }
    ) -> EventLoopFuture<Void> {
        self.asyncFileSend(.PUT, to: url, file: file, beforeSend: beforeSend, afterSend: afterSend, progress: progress)
    }

    /// 通用异步文件上传方法（默认参数实现）
    /// - 实现流程：
    ///   1. 在fileEventLoop中执行文件操作
    ///   2. 打开文件并获取元信息
    ///   3. 创建分块迭代器
    ///   4. 调用流式上传方法
    ///   5. 确保文件句柄关闭
    @Sendable func asyncFileSend(
        _ method: HTTPMethod,
        to url: URI,
        file: String,
        beforeSend: @escaping BeforeSendAction = { _, _ in },
        afterSend: @escaping AsyncAfterSendAction = defaultAfterSend,
        progress: @escaping ProgressAction = { _ in }
    ) -> EventLoopFuture<Void> {
        return fileEventLoop.makeFutureWithTask {
            let filePath = FilePath(file)
            let fileHandle = try await FileSystem.shared.openFile(forReadingAt: filePath, options: .init())
            do {
                // 1. 验证文件有效性
                guard
                    let fileName = filePath.lastComponent?.string,
                    let info = try await FileSystem.shared.info(forFileAt: filePath)
                else {
                    throw WSMClientErr.fileInfoGetFailed.d(14034, #file, #line)
                }
                
                // 2. 创建分块迭代器（每块最大ChunkTool.maxChunk字节）
                let chunkIterator = FileChunksIterator(
                    fileHandle.readChunks(
                        in: 0..<info.size,
                        chunkLength: .bytes(.init(ChunkTool.maxChunk))
                    ).makeAsyncIterator()
                )
                
                // 3. 执行流式上传
                try await streamSend(
                    method,
                    to: url,
                    headers: ["Content-Disposition": fileName],
                    bodySize: Int(info.size),
                    stream: { request, channel, maxChunk, currentIndex in
                        guard let data = try await chunkIterator.next() else {
                            throw WSMClientErr.fileOperationUnknowErr.d("未成功读出数据", 14035, (#file, #line))
                        }
                        return data
                    },
                    beforeSend: beforeSend,
                    afterSend: { try await afterSend($0).get() },
                    progress: progress
                )
                
                // 4. 正常关闭文件
                try await fileHandle.close()
            } catch {
                // 5. 异常时确保关闭文件
                try await fileHandle.close()
                throw WSMClientErr.fileOperationUnknowErr.d(14033, #file, #line).subErr(error)
            }
        }
    }
}

final class FileChunksIterator: @unchecked Sendable {
    var iterator: FileChunks.FileChunkIterator {
        get {
            lock.withLock {
                return _iterator
            }
        }
        set {
            lock.withLock {
                _iterator = newValue
            }
        }
    }

    private let lock = NIOLock()
    private var _iterator: FileChunks.FileChunkIterator

    init(_ iterator: FileChunks.FileChunkIterator) {
        self._iterator = iterator
    }

    @Sendable func next() async throws -> ByteBuffer? { try await iterator.next() }
}

enum WSMClientErr: String, ErrList {
    var domain: String { "woo.sys.wsmclient.err" }
    case fileInfoGetFailed = "文件信息获取失败"
    case fileOperationUnknowErr = "文件操作时出现未知错误"
    case fileReadFailed = "文件读取时失败"
    case fileReadUnknowErr = "文件读取时遇到未知错误"
}
