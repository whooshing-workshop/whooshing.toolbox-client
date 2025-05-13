import NIOCore
import ErrorHandle
import Foundation

public protocol BodyCodable {
    var body: ByteBuffer? { get set }
    mutating func jsonBodyEncode<T: Encodable>(_ value: T) throws
    func jsonBodyDecode<T: Decodable>(_ type: T.Type) throws -> T
}

public enum BodyCodableErr: String, ErrList {
    public var domain: String { "woo.sys.body.codable.protocol.err" }
    case bodyEncodeFailed = "请求体编码失败"
    case bodyDecodeFailed = "响应体解码失败"
}

public extension BodyCodable {
    mutating func jsonBodyEncode<T: Encodable>(_ value: T) throws {
        do {
            var buffer = ByteBuffer()
            try JSONEncoder().encode(value, into: &buffer)
            self.body = buffer
        } catch {
            throw BodyCodableErr.bodyEncodeFailed.d(14085, (#file, #line)).subErr(error)
        }
    }
    
    func jsonBodyDecode<T: Decodable>(_ type: T.Type) throws -> T {
        guard let body = body else {
            throw BodyCodableErr.bodyDecodeFailed.d("响应体不存在", 14083, (#file, #line))
        }
        
        do {
            return try JSONDecoder().decode(T.self, from: body)
        } catch {
            throw BodyCodableErr.bodyDecodeFailed.d(14084, (#file, #line)).subErr(error)
        }
    }
}
