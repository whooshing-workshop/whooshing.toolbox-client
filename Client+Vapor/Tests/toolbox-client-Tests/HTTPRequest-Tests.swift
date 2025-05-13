import Testing
@testable import WhooshingClient
import NIOCore
import NIOHTTP1
import Foundation
import Logging

@Suite("HTTPRequest 测试")
struct HTTPRequestTests {
    
    struct Payload: Codable, Equatable {
        let name: String
        let age: Int
    }

    @Test("使用所有参数初始化")
    func testInit() {
        let uri = WebURI(stringLiteral: "https://localhost/api")
        let method: HTTPMethod = .GET
        let version = HTTPVersion(major: 1, minor: 1)
        let headers = HTTPHeaders([("X-Test", "true")])
        var buffer = ByteBufferAllocator().buffer(capacity: 5)
        buffer.writeString("hello")
        let request = HTTPRequest(method: method, url: uri, version: version, headers: headers, body: buffer)
        #expect(request.method == .GET)
        #expect(request.url.string == "https://localhost/api")
        #expect(request.url.path == "/api")
        #expect(request.version.major == 1)
        #expect(request.headers["X-Test"] == ["true"])
        #expect(request.body?.readableBytes == 5)
    }

    @Test("Codable 编解码往返")
    func testCodable() throws {
        let uri = WebURI(stringLiteral: "https://localhost/json")
        let headers = HTTPHeaders([("Content-Type", "application/json")])
        var buffer = ByteBufferAllocator().buffer(capacity: 0)
        let payload = Payload(name: "Alice", age: 30)
        let json = try JSONEncoder().encode(payload)
        buffer.writeBytes(json)
        let original = HTTPRequest(method: .POST, url: uri, version: .http1_1, headers: headers, body: buffer)
        let encoded = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(HTTPRequest.self, from: encoded)
        #expect(decoded.method == .POST)
        #expect(decoded.url.string == "https://localhost/json")
        #expect(decoded.url.path == "/json")
        let bodyDecoded = try decoded.jsonBodyDecode(Payload.self)
        #expect(bodyDecoded == payload)
    }

    @Test("描述字符串输出")
    func testDescription() {
        var buffer = ByteBufferAllocator().buffer(capacity: 5)
        buffer.writeString("world")
        let req = HTTPRequest(method: .PUT, url: WebURI(stringLiteral: "https://localhost/put"), headers: ["Content-Length": "5"], body: buffer)
        let desc = req.description
        #expect(desc.contains("PUT /put HTTP/1.1"))
        #expect(desc.contains("Content-Length: 5"))
        #expect(desc.contains("world"))
    }

    @Test("生成数据缓冲区")
    func testDataBuffer() throws {
        var buffer = ByteBufferAllocator().buffer(capacity: 0)
        buffer.writeString("abc123")
        let request = HTTPRequest(method: .PATCH, url: WebURI(stringLiteral: "https://localhost/patch"), body: buffer)
        let (headerBuffer, bodyBuffer) = try request.data(bufferAllocator: .init())
        let headerStr = headerBuffer.getString(at: 0, length: headerBuffer.readableBytes) ?? ""
        #expect(headerStr.contains("PATCH /patch HTTP/1.1"))
        #expect(headerStr.contains("Content-Length") == false) // 未在头部中设置
        #expect(bodyBuffer?.readableBytes == 6)
    }

    @Test("空请求体解码应抛出错误")
    func testDecodeFail() throws {
        let request = HTTPRequest(method: .GET, url: WebURI(stringLiteral: "https://localhost/empty"))
        #expect(throws: Error.self, performing: { try request.jsonBodyDecode(Payload.self) })
    }
}
