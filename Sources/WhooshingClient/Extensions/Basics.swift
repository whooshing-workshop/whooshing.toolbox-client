import DataConvertable
import Foundation
import Cryptos
import NIOCore
import NIOFoundationCompat
import NIOHTTP1

extension ChannelHandlerContext: @retroactive @unchecked Sendable {}
extension HTTPRequestEncoder: @retroactive @unchecked Sendable {}
extension NIOHTTPRequestHeadersValidator: @retroactive @unchecked Sendable {}

public extension URL {
    func toUri(with path: String) -> WebURI { .init(stringLiteral: self.absoluteString + path) }
}
