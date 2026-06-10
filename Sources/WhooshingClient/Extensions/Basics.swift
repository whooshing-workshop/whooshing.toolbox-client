import DataConvertable
import Foundation
import Cryptos
import NIOCore
import NIOFoundationCompat
import NIOHTTP1

public extension URL {
    @inlinable
    func toUri(with path: String) -> WebURI { .init(stringLiteral: self.absoluteString + path) }
}
