import NIOCore
import AsyncAlgorithms
import NIOHTTP1

public struct HTTPBody: Sendable {
    public enum `Type`: Sendable {
        case bytes(ByteBuffer)
        case stream(AsyncThrowingChannel<ByteBuffer, Error>)
    }
    
    public let type: `Type`
    public let headers: HTTPHeaders
    
    init(type: `Type`, headers: HTTPHeaders = ["content-type": "application/octet-stream"]) {
        self.type = type
        self.headers = headers
    }
}
