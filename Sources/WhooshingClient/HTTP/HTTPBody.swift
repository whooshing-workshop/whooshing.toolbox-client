import NIOCore
import Foundation
import DataConvertable
import NIOFileSystem
import ErrorHandle
import NIOHTTP1



public struct HTTPBody: Sendable {
    public enum `Type`: Sendable {
        case bytes(ByteBuffer)
        case stream(AsyncThrowingStream<ByteBuffer, Error>)
    }
    
    public let type: `Type`
    public let headers: HTTPHeaders
    
    init(type: `Type`, headers: HTTPHeaders = ["content-type": "application/octet-stream"]) {
        self.type = type
        self.headers = headers
    }
}
