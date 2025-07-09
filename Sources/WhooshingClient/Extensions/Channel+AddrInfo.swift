import NIOCore

public extension Channel {
    @inlinable
    var remoteAddrInfo: String {
        if let addr = self.remoteAddress {
            return "\(addr.ipAddress ?? "unknow"):\(addr.port ?? -1)"
        }
        return "unknow"
    }

    @inlinable
    var localAddrInfo: String {
        if let addr = self.localAddress {
            return "\(addr.ipAddress ?? "unknow"):\(addr.port ?? -1)"
        }
        return "unknow"
    }

    @inlinable
    var clientAddrInfo: String { "\(localAddrInfo) to \(remoteAddrInfo)" }
    @inlinable
    var serverAddrInfo: String { "\(localAddrInfo) from \(remoteAddrInfo)" }
}
