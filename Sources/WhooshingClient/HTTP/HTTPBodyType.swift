import NIOCore
import ErrorHandle
import Foundation
import NIOHTTP1
import DataConvertable

/// 该文件定义了 HTTP 请求体的一般格式(Content-Type)，分别为
///
/// - text: text/plain
/// - buffer 或 data: application/octet-stream
/// - json: application/json
///
/// 分别对应 Swift 的
///
/// - String
/// - BufferByte 或 Data
/// - 遵循 Codable 的类型
///
/// 搭配 ``HTTPRequest`` 和 ``HTTPResponse``，通过
///
/// `request(or response).bodyEncode(value, as: HTTPBody.text)`
/// `request(or response).bodyEncode(value, as: HTTPBody.buffer)`
/// `request(or response).bodyEncode(value, as: HTTPBody.data)`
/// `.....................bodyDecode(to: HTTPBody.text) -> String`
/// `.....................bodyDecode(to: HTTPBody.buffer) -> ByteBuffer`
/// `.....................bodyDecode(to: HTTPBody.data) -> Data`
///
/// 将 value 编码或解码请求体或响应体，对于 json 格式的数据类型，通过
///
/// `request(or response).jsonBodyEncode(value)`
/// `request(or response).jsonBodyDecode(YourJsonType.self) -> YourJsonType`
///
/// 这需要 value 遵循 ``Encodable`` 协议，YourJsonType 遵循 ``Decodable`` 协议
///
/// 另见 ``BodyCodable`` 协议


/// 表示 HTTP 请求或响应体的封装类型，用于在框架中支持多种编码与解码方式。
public enum HTTPBody {
    /// 文本类型（plain text）
    public static let text = Text.self
    /// ByteBuffer 类型，适合处理二进制或流式数据
    public static let buffer = Buffer.self
    /// Foundation 中的 Data 类型，适合处理内存数据块
    public static let data = WData.self
    
    /// 生成 JSON 编码器类型，支持泛型结构体
    public static func jsonEncode<T: Encodable>(_ type: T.Type) -> Json<T, NULL>.Type { Json<T, NULL>.self }
    /// 生成 JSON 解码器类型，支持泛型结构体
    public static func jsonDecode<T: Decodable>(_ type: T.Type) -> Json<NULL, T>.Type { Json<NULL, T>.self }
}

public extension HTTPBody {
    /// 同时支持编码与解码的复合协议
    protocol Typee: Encode, Decode where EValue == DValue {}
    
    /// 空类型，用作 JSON 编解码中占位泛型
    struct NULL: Codable {}
    
    /// 定义编码行为的协议
    protocol Encode: Sendable {
        /// 编码类型
        associatedtype EValue
        /// 编码类型的 MIME 名称
        static var name: String { get }
        /// 将指定类型数据编码为 ByteBuffer
        static func encode(data: EValue) throws -> ByteBuffer
    }
    
    /// 定义解码行为的协议
    protocol Decode: Sendable {
        /// 解码后的类型
        associatedtype DValue
        /// 解码类型的 MIME 名称
        static var name: String { get }
        /// 从 ByteBuffer 解码为指定类型数据
        static func decode(data: ByteBuffer) throws -> DValue
    }
    
    /// 文本类型的实现，支持编码与解码字符串
    struct Text: Typee, Sendable {
        public typealias EValue = String
        public static var name: String { "text/plain" }
    }
    
    /// ByteBuffer 类型的实现，直接处理二进制内容
    struct Buffer: Typee, Sendable {
        public typealias EValue = ByteBuffer
        public static var name: String { "application/octet-stream" }
    }
    
    /// Foundation 中的 Data 类型实现，用于处理 NSData 类型数据
    struct WData: Typee, Sendable {
        public typealias EValue = Data
        public static var name: String { "application/octet-stream" }
    }
    
    /// JSON 编解码器，支持自定义编码类型和解码类型
    struct Json<EValue, DValue>: Encode, Decode, Sendable where EValue: Encodable, DValue: Decodable {
        /// 返回对应的 MIME 类型
        public static var name: String { "application/json" }
        /// 使用 JSONEncoder 将数据编码为 ByteBuffer
        public static func encode(data: EValue) throws -> ByteBuffer {
            var buffer = ByteBuffer()
            try JSONEncoder().encode(data, into: &buffer)
            return buffer
        }
        /// 使用 JSONDecoder 将 ByteBuffer 中的数据解码为目标类型
        public static func decode(data: ByteBuffer) throws -> DValue {
            try JSONDecoder().decode(DValue.self, from: data)
        }
    }
}

/// 默认实现：当类型符合 ThrowableDataConvertable 协议时的编码逻辑
public extension HTTPBody.Encode where EValue: ThrowableDataConvertable {
    static func encode(data: EValue) throws -> ByteBuffer { try .init(data: data.data()) }
}

/// 默认实现：当目标类型符合 ThrowableDataConvertable 协议时的解码逻辑
public extension HTTPBody.Decode where DValue: ThrowableDataConvertable {
    static func decode(data: ByteBuffer) throws -> DValue { try .init(data: Data(buffer: data)) }
}
