import Vapor
import DataConvertable
import Cryptos
import NIO

extension Data: @retroactive AsyncResponseEncodable {}
extension Data: @retroactive AsyncRequestDecodable {}
extension Data: @retroactive ResponseEncodable {}
extension Data: @retroactive RequestDecodable {}
extension Data: @retroactive Content {}


extension Crypto.Symm.Key: @retroactive @unchecked Sendable {}
extension Crypto.Symm.Key: @retroactive AsyncResponseEncodable {}
extension Crypto.Symm.Key: @retroactive AsyncRequestDecodable {}
extension Crypto.Symm.Key: @retroactive ResponseEncodable {}
extension Crypto.Symm.Key: @retroactive RequestDecodable {}
extension Crypto.Symm.Key: @retroactive Content {}


extension Crypto.Asym.CPrivateKey: @retroactive @unchecked Sendable {}
extension Crypto.Asym.CPrivateKey: @retroactive AsyncResponseEncodable {}
extension Crypto.Asym.CPrivateKey: @retroactive AsyncRequestDecodable {}
extension Crypto.Asym.CPrivateKey: @retroactive ResponseEncodable {}
extension Crypto.Asym.CPrivateKey: @retroactive RequestDecodable {}
extension Crypto.Asym.CPrivateKey: @retroactive Content {}


extension Crypto.Asym.CPublicKey: @retroactive @unchecked Sendable {}
extension Crypto.Asym.CPublicKey: @retroactive AsyncResponseEncodable {}
extension Crypto.Asym.CPublicKey: @retroactive AsyncRequestDecodable {}
extension Crypto.Asym.CPublicKey: @retroactive ResponseEncodable {}
extension Crypto.Asym.CPublicKey: @retroactive RequestDecodable {}
extension Crypto.Asym.CPublicKey: @retroactive Content {}


extension Crypto.Asym.SPrivateKey: @retroactive @unchecked Sendable {}
extension Crypto.Asym.SPrivateKey: @retroactive AsyncResponseEncodable {}
extension Crypto.Asym.SPrivateKey: @retroactive AsyncRequestDecodable {}
extension Crypto.Asym.SPrivateKey: @retroactive ResponseEncodable {}
extension Crypto.Asym.SPrivateKey: @retroactive RequestDecodable {}
extension Crypto.Asym.SPrivateKey: @retroactive Content {}


extension Crypto.Asym.SPublicKey: @retroactive @unchecked Sendable {}
extension Crypto.Asym.SPublicKey: @retroactive AsyncResponseEncodable {}
extension Crypto.Asym.SPublicKey: @retroactive AsyncRequestDecodable {}
extension Crypto.Asym.SPublicKey: @retroactive ResponseEncodable {}
extension Crypto.Asym.SPublicKey: @retroactive RequestDecodable {}
extension Crypto.Asym.SPublicKey: @retroactive Content {}


extension ByteBuffer: SafeDataConvertable {
    public func data() -> Data { .init(buffer: self) }
}

public extension Channel {
    var remoteAddrInfo: String {
        if let addr = self.remoteAddress {
            return "\(addr.ipAddress ?? "unknow"):\(addr.port ?? -1)"
        }
        return "unknow"
    }

    var localAddrInfo: String {
        if let addr = self.localAddress {
            return "\(addr.ipAddress ?? "unknow"):\(addr.port ?? -1)"
        }
        return "unknow"
    }

    var clientAddrInfo: String { "\(localAddrInfo) to \(remoteAddrInfo)" }
    var serverAddrInfo: String { "\(localAddrInfo) from \(remoteAddrInfo)" }
}

public extension URL {
    func toUri(with path: String) -> URI { .init(string: self.absoluteString + path) }
}

public func streamingHandle(
    chunkData: inout ByteBuffer,
    context: ChannelHandlerContext,
    bufferStrategy: BufferStrategy,
    dic: SendableDictionary<ObjectIdentifier, ByteBuffer>, 
    streaming: Bool) -> EventLoopFuture<ByteBuffer?> 
{
    if case .collect = bufferStrategy {
        let id = ObjectIdentifier(context.channel)
        if streaming {
            if var data = dic[id] {
                data.writeBuffer(&chunkData)
                dic[id] = data
            } else {
                dic[id] = chunkData
            }
            return context.eventLoop.makeSucceededFuture(nil)
        } else {
            var data = dic[id]
            dic[id] = nil
            return context.eventLoop.makeSucceededFuture(data == nil ? chunkData : { data!.writeBuffer(&chunkData); return data! }())
        }
    } else {
        return context.eventLoop.makeSucceededFuture(nil)
    }
}
