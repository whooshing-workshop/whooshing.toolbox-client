import NIOCore
import ErrorHandle
import Foundation
import NIOHTTP1
import DataConvertable

/// 用于支持 HTTP 请求体（body）与头部（headers）的通用协议。
/// 提供编码（encode）与解码（decode）能力，适配不同的 `HTTPBody` 编码类型。
public protocol BodyCodable {
    /// 请求或响应体的内容（ByteBuffer 格式）
    var body: ByteBuffer? { get set }

    /// HTTP 请求头或响应头
    var headers: HTTPHeaders { get set }

    /// 使用指定的编码类型将值编码为 ByteBuffer 并写入 body 与 headers
    /// - Parameters:
    ///   - value: 要编码的值
    ///   - bodyType: 编码器类型，必须符合 `HTTPBody.Encode`
    mutating func bodyEncode<T: HTTPBody.Encode>(_ value: T.EValue, as bodyType: T.Type) throws

    /// 使用指定的解码类型将 body 内容解码为期望类型
    /// - Parameter type: 解码器类型
    /// - Returns: 解码得到的值
    func bodyDecode<T: HTTPBody.Decode>(to type: T.Type) throws -> T.DValue

    /// 以 JSON 格式编码对象为请求体内容
    /// - Parameter value: 任意 Encodable 对象
    mutating func jsonBodyEncode<T: Encodable>(_ value: T) throws

    /// 将请求体内容按 JSON 解码为指定类型
    /// - Parameter type: 解码目标类型
    func jsonBodyDecode<T: Decodable>(_ type: T.Type) throws -> T
}

/// BodyCodable 协议内部错误，用于标识 body 编码/解码异常
public enum BodyCodableErr: String, ErrList {
    public var domain: String { "woo.sys.body.codable.protocol.err" }

    /// 编码失败
    case bodyEncodeFailed = "请求体编码失败"

    /// 解码失败
    case bodyDecodeFailed = "响应体解码失败"
}

public extension BodyCodable {
    /// 默认实现：使用指定编码类型将值编码为 ByteBuffer，并自动设置 content-type 与 content-length
    mutating func bodyEncode<T: HTTPBody.Encode>(_ value: T.EValue, as bodyType: T.Type) throws {
        do {
            let buffer = try T.encode(data: value)
            self.body = buffer
            self.headers.replaceOrAdd(name: "content-type", value: T.name)
            self.headers.replaceOrAdd(name: "content-length", value: String(buffer.readableBytes))
        } catch {
            throw BodyCodableErr.bodyEncodeFailed.d(14085).subErr(error)
        }
    }

    /// 默认实现：使用指定解码类型将 body 解码为目标值类型
    func bodyDecode<T: HTTPBody.Decode>(to type: T.Type) throws -> T.DValue {
        guard let body = body else {
            throw BodyCodableErr.bodyDecodeFailed.d("响应体不存在", 14083)
        }
        do {
            return try T.decode(data: body)
        } catch {
            throw BodyCodableErr.bodyDecodeFailed.d(14084).subErr(error)
        }
    }

    /// 默认实现：以 JSON 编码对象并设置相应头部信息
    mutating func jsonBodyEncode<T: Encodable>(_ value: T) throws {
        try bodyEncode(value, as: HTTPBody.jsonEncode(T.self))
    }

    /// 默认实现：将 JSON 格式的 body 解码为指定类型
    func jsonBodyDecode<T: Decodable>(_ type: T.Type) throws -> T {
        try bodyDecode(to: HTTPBody.jsonDecode(T.self))
    }
}
