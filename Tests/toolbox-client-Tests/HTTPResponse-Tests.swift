import Testing
@testable import WhooshingClient
import NIOHTTP1
import NIOCore
import Foundation

extension String: @retroactive Error {}

@Suite("HTTPResponse Tests")
struct HTTPResponseTests {
    
    struct Payload: Codable, Equatable {
        let message: String
    }

    @Test("初始化 HTTPResponse")
    func testInit() {
        let version = HTTPVersion(major: 1, minor: 1)
        let status = HTTPResponseStatus.ok
        let headers = HTTPHeaders([("Content-Type", "text/plain")])
        var buffer = ByteBufferAllocator().buffer(capacity: 5)
        buffer.writeString("hello")
        let response = HTTPResponse(status: status, body: buffer, version: version, headers: headers)
        #expect(response.version.major == 1)
        #expect(response.status == .ok)
        #expect(response.headers.first?.name == "Content-Type")
        #expect(response.body?.readableBytes == 5)
    }

    @Test("description 输出应包含头部和主体")
    func testDescription() {
        var buffer = ByteBufferAllocator().buffer(capacity: 5)
        buffer.writeString("world")
        let response = HTTPResponse(status: .notFound, body: buffer, version: .http1_1, headers: ["X-Header": "val"])
        let desc = response.description
        #expect(desc.contains("HTTP/1.1 404 Not Found"))
        #expect(desc.contains("X-Header: val"))
        #expect(desc.contains("world"))
    }

    @Test("从 ByteBuffer 解析生成 HTTPResponse")
    func testDecodeFromBuffer() throws {
        let allocator = ByteBufferAllocator()
        var buffer = allocator.buffer(capacity: 128)
        buffer.writeString("HTTP/1.1 200 OK\r\n")
        buffer.writeString("X-Test: yes\r\n")
        buffer.writeString("Content-Length: 6\r\n")
        buffer.writeString("\r\n")
        buffer.writeString("abc123")
        
        let response = try HTTPResponse(data: buffer)
        
        #expect(response.status == .ok)
        #expect(response.headers["X-Test"] == ["yes"])
        var copy = try #require(response.body)
        #expect(copy.readString(length: copy.readableBytes) == "abc123")
    }

    @Test("Codable 编解码应成功")
    func testCodableRoundTrip() throws {
        var buffer = ByteBufferAllocator().buffer(capacity: 0)
        let payload = Payload(message: "hi")
        let json = try JSONEncoder().encode(payload)
        buffer.writeBytes(json)

        let response = HTTPResponse(status: .ok, body: buffer, version: .http1_1, headers: ["Content-Type": "application/json"])
        let encoded = try JSONEncoder().encode(response)
        let decoded = try JSONDecoder().decode(HTTPResponse.self, from: encoded)
        #expect(decoded.status == .ok)
        let decodedPayload = try decoded.jsonBodyDecode(Payload.self)
        #expect(decodedPayload == payload)
    }

    @Test("空体应导致解码失败")
    func testEmptyBodyDecodeFails() {
        let response = HTTPResponse(status: .ok, body: nil, version: .http1_1, headers: [:])
        #expect(throws: Error.self, performing: { try response.jsonBodyDecode(Payload.self) })
    }
}
