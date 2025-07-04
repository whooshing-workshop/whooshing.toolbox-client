import ErrorHandle

public extension HttpsClient {
    @frozen
    enum Errcase: String, ErrList, Sendable {
        public typealias ErrType = WhooshingClientError<HttpsClient>
        
        case responseParseFailed = "解析响应失败"
        case streamingEngageFailed = "流传输数据获取失败"
        case requestSendFailed = "请求发送失败"
        case urlConnectionFailed = "对该 url 目标地址连接失败"
        case responseNotValid = "对方响应不合法"
    }
}

public extension ApiClient {
    @frozen
    enum Errcase: String, ErrList, Sendable {
        public typealias ErrType = WhooshingClientError<ApiClient>
        
        case badRequest = "无效的请求"
        case badResponse = "无效的相应"
        case encryptFailed = "交接协议协议加密失败"
        case decryptFailed = "交接协议信息解密失败"
        case jsonEncodeFailed = "交接协议信息 json 编码失败"
        case jsonDecodeFailed = "交接协议信息 json 解码失败"
        case channelAssignFailed = "通道分配失败"
        case tcpSendFailed = "TCP 通道数据发送失败"
        case tcpHandlerRemoveFailed = "TCP 处理器移除失败"
        case internalFailure = "内部未知错误"
    }
}

@frozen
public struct WhooshingClientError<Client>: Err, Sendable where Client: WhooshingClient {
    /// 该错误的错误枚举值。
    public var error: Client.Errcase!
    /// 每次发生错误时，可以自行阐述一些附加说明。
    public var explain: String?
    /// 发生错误的文件名称。
    public var file: String!
    /// 发生错误的行数。
    public var line: Int!
    /// 发生错误的函数。
    public var function: String!
    /// 该错误的子错误
    public var subError: Error?

    /// 空初始化函数，用于默认构造实例
    @inlinable
    public init() {}
}
