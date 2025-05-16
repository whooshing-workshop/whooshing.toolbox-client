import NIOCore
import ErrorHandle
import Foundation
import NIOHTTP1
import DataConvertable

public protocol BodyCodable {
    var body: ByteBuffer? { get set }
    var headers: HTTPHeaders { get set }
    mutating func bodyEncode<T: HTTPBody.Encode>(_ value: T.EValue, as bodyType: T.Type) throws
    func bodyDecode<T: HTTPBody.Decode>(to type: T.Type) throws -> T.DValue
    mutating func jsonBodyEncode<T: Encodable>(_ value: T) throws
    func jsonBodyDecode<T: Decodable>(_ type: T.Type) throws -> T
}

public enum BodyCodableErr: String, ErrList {
    public var domain: String { "woo.sys.body.codable.protocol.err" }
    case bodyEncodeFailed = "请求体编码失败"
    case bodyDecodeFailed = "响应体解码失败"
}

public extension BodyCodable {
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
    
    mutating func jsonBodyEncode<T: Encodable>(_ value: T) throws {
        try bodyEncode(value, as: HTTPBody.jsonEncode(T.self))
    }
    
    func jsonBodyDecode<T: Decodable>(_ type: T.Type) throws -> T {
        try bodyDecode(to: HTTPBody.jsonDecode(T.self))
    }
}
