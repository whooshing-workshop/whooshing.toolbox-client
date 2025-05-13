import NIOCore

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
