import DataConvertable
import Foundation

public extension URL {
    @inlinable
    func toUri(with path: String) -> WebURI { .init(stringLiteral: self.absoluteString + path) }
}
