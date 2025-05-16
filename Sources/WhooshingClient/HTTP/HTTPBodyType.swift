import NIOCore
import ErrorHandle
import Foundation
import NIOHTTP1
import DataConvertable

public enum HTTPBody {
    public static let text = Text.self
    public static let buffer = Buffer.self
    public static let data = WData.self
    
    public static func jsonEncode<T: Encodable>(_ type: T.Type) -> Json<T, NULL>.Type { Json<T, NULL>.self }
    public static func jsonDecode<T: Decodable>(_ type: T.Type) -> Json<NULL, T>.Type { Json<NULL, T>.self }
}

public extension HTTPBody {
    protocol Typee: Encode, Decode where EValue == DValue {}
    
    struct NULL: Codable {}
    
    protocol Encode: Sendable {
        associatedtype EValue
        static var name: String { get }
        static func encode(data: EValue) throws -> ByteBuffer
    }
    
    protocol Decode: Sendable {
        associatedtype DValue
        static var name: String { get }
        static func decode(data: ByteBuffer) throws -> DValue
    }
    
    struct Text: Typee, Sendable {
        public typealias EValue = String
        public static var name: String { "text/plain" }
    }
    
    struct Buffer: Typee, Sendable {
        public typealias EValue = ByteBuffer
        public static var name: String { "application/octet-stream" }
    }
    
    struct WData: Typee, Sendable {
        public typealias EValue = Data
        public static var name: String { "application/octet-stream" }
    }
    
    struct Json<EValue, DValue>: Encode, Decode, Sendable where EValue: Encodable, DValue: Decodable {
        public static var name: String { "application/json" }
        public static func encode(data: EValue) throws -> ByteBuffer {
            var buffer = ByteBuffer()
            try JSONEncoder().encode(data, into: &buffer)
            return buffer
        }
        public static func decode(data: ByteBuffer) throws -> DValue {
            try JSONDecoder().decode(DValue.self, from: data)
        }
    }
}

public extension HTTPBody.Encode where EValue: ThrowableDataConvertable {
    static func encode(data: EValue) throws -> ByteBuffer { try .init(data: data.data()) }
}

public extension HTTPBody.Decode where DValue: ThrowableDataConvertable {
    static func decode(data: ByteBuffer) throws -> DValue { try .init(data: Data(buffer: data)) }
}
