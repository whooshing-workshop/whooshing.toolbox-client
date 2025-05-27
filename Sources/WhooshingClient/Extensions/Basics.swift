import DataConvertable
import Foundation
import Cryptos
import NIOCore
import NIOFoundationCompat
import NIOHTTP1

extension ChannelHandlerContext: @retroactive @unchecked Sendable {}
extension HTTPRequestEncoder: @retroactive @unchecked Sendable {}
extension NIOHTTPRequestHeadersValidator: @retroactive @unchecked Sendable {}

extension ByteBuffer: @retroactive ThrowableDataConvertable {}
extension ByteBuffer: @retroactive SafeDataConvertable {
    public func data() -> Data { .init(buffer: self) }
}

public extension URL {
    func toUri(with path: String) -> WebURI { .init(stringLiteral: self.absoluteString + path) }
}
