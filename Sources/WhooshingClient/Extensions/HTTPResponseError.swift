import ErrorHandle
import NIOHTTP1

#if WHOOSHING_VAPOR
import Vapor
#endif

/// 表示一个带有 HTTP 响应状态码的错误类型，可用于 Web 框架（如 Vapor）中统一处理错误响应。
public struct HTTPResponseError: Err {
    /// 附加类型为 HTTP 响应状态码（HTTPResponseStatus）
    public typealias AdditionType = HTTPResponseStatus
    
    /// HTTP 响应状态码，例如 404 Not Found、500 Internal Server Error 等
    public var status: HTTPResponseStatus { __status }
    
    /// 错误原因说明，默认使用 description 实现
    public var reason: String { self.description }
    
    /// 错误所属域，用于区分不同模块或系统
    public var domain: String!
    
    /// 错误简要摘要，适合展示给用户或日志记录
    public var summary: String!
    
    /// 错误详细解释，供开发者进一步理解问题原因
    public var explain: String?
    
    /// 抛出该错误的文件名，自动捕获或手动设置
    public var file: String!
    
    /// 抛出该错误的代码行号
    public var line: Int!
    
    /// 可选的标记位置，用于定位子结构或上下文
    public var mark: Int?
    
    /// 可选的子错误，可用于嵌套错误信息
    public var subError: Error?
    
    /// 实际存储的 HTTP 状态码
    private var __status: HTTPResponseStatus!
    
    /// 空初始化函数，用于默认构造实例
    public init() {}
    
    /// 初始化附加状态码，通常由框架或中间件调用
    /// - Parameters:
    ///   - status: 要附加的 HTTP 响应状态码
    ///   - new: 传入的错误实例引用，将被更新
    public func initAdds(_ status: HTTPResponseStatus, new: inout Self) {
        new.__status = status
    }
}

#if WHOOSHING_VAPOR
/// 当使用 Vapor 框架时，将该错误类型扩展为 AbortError，使其可用于响应错误中断
extension HTTPResponseError: AbortError {}
#endif
