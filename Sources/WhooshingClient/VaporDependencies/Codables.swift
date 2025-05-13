import NIOHTTP1

extension HTTPResponseStatus: Codable {
    public init(from decoder: Decoder) throws {
        let code = try decoder.singleValueContainer().decode(Int.self)
        self = .init(statusCode: code)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(self.code)
    }
}

extension HTTPHeaders: Codable {
    private enum CodingKeys: String, CodingKey { case name, value }
    
    public init(from decoder: any Decoder) throws {
        self.init()
        do {
            var container = try decoder.unkeyedContainer()
            
            while !container.isAtEnd {
                let nested = try container.nestedContainer(keyedBy: Self.CodingKeys.self)
                let name = try nested.decode(String.self, forKey: .name)
                let value = try nested.decode(String.self, forKey: .value)
                
                self.add(name: name, value: value)
            }
        } catch DecodingError.typeMismatch(let type, _) where "\(type)".starts(with: "Array<") {
            // Try the old format
            let container = try decoder.singleValueContainer()
            let dict = try container.decode([String: String].self)
            
            self.add(contentsOf: dict.map { ($0.key, $0.value) })
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.unkeyedContainer()
        
        for (name, value) in self {
            var nested = container.nestedContainer(keyedBy: Self.CodingKeys.self)
            
            try nested.encode(name, forKey: .name)
            try nested.encode(value, forKey: .value)
        }
    }
}
