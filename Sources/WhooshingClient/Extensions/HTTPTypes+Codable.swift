import NIOHTTP1

extension HTTPVersion: @retroactive Codable {
    @inlinable
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let major = try container.decode(Int.self, forKey: .major)
        let minor = try container.decode(Int.self, forKey: .minor)
        self.init(major: major, minor: minor)
    }
    
    @inlinable
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(major, forKey: .major)
        try container.encode(minor, forKey: .minor)
    }
    
    @usableFromInline
    enum CodingKeys: String, CodingKey {
        case major
        case minor
    }
}

extension HTTPMethod: @retroactive Codable {
    @inlinable
    public init(from decoder: any Decoder) throws {
        let name = try decoder.singleValueContainer().decode(String.self)
        self = .init(rawValue: name)
    }
    
    @inlinable
    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(self.rawValue)
    }
}
