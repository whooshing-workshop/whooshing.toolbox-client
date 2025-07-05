import ErrorHandle

public extension HttpsClient {
    @frozen
    enum Errcase: String, ErrList, Sendable {
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
        case badRequest = "无效的请求"
        case badResponse = "无效的响应"
        case encryptFailed = "交接协议协议加密失败"
        case decryptFailed = "交接协议信息解密失败"
        case jsonEncodeFailed = "交接协议信息 json 编码失败"
        case jsonDecodeFailed = "交接协议信息 json 解码失败"
        case tcpChannelAssignFailed = "TCP 通道分配失败"
        case tcpSendFailed = "TCP 通道数据发送失败"
        case tcpHandlerRemoveFailed = "TCP 处理器移除失败"
        case internalFailure = "内部错误"
    }
}
