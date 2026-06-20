import Testing
import NIOEmbedded
import Foundation
@testable import WhooshingClient

@Suite("Pipeline 测试集")
struct PipelineHandler {
    @Test("基本测试")
    func basicTest() async throws {
        let channel = EmbeddedChannel()
        
        try await channel.pipeline.addHandler(RequestWrapperHandler(logger: nil))
        
        let req = HTTPRequest(method: .GET, url: "http://localhost:8080/hi")
        
        try channel.writeOutbound(req)
        
        var out = try #require(try channel.readOutbound(as: HTTPClientRequestPart.self))
        
        switch out {
        case .head(let head):
            #expect(head.uri == "/hi")
            #expect(head.method == .GET)
        default:
            #expect(throws: Error.self) {}
        }
        
        out = try #require(try channel.readOutbound(as: HTTPClientRequestPart.self))
        
        switch out {
        case .end(_):
            break
        default:
            #expect(throws: Error.self) {}
        }
    }
}
