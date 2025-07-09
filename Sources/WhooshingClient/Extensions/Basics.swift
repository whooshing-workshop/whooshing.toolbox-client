import DataConvertable
import Foundation
import Cryptos
import NIOCore
import NIOFoundationCompat
import NIOHTTP1

extension ChannelHandlerContext: @retroactive @unchecked Sendable {}
extension HTTPRequestEncoder: @retroactive @unchecked Sendable {}
extension NIOHTTPRequestHeadersValidator: @retroactive @unchecked Sendable {}

extension Crypto.Symm.Key: @unchecked Sendable{}
extension Crypto.Asym.CPrivateKey: @unchecked Sendable{}
extension Crypto.Asym.CPublicKey: @unchecked Sendable{}
extension Crypto.Asym.SPrivateKey: @unchecked Sendable{}
extension Crypto.Asym.SPublicKey: @unchecked Sendable{}

public extension URL {
    @inlinable
    func toUri(with path: String) -> WebURI { .init(stringLiteral: self.absoluteString + path) }
}
