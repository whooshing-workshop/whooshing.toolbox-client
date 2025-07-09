import Testing
import AsyncAlgorithms
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
    func testInit() throws {
        let uri = WebURI(stringLiteral: "https://localhost/api")
        let method: HTTPMethod = .GET
        let version = HTTPVersion(major: 1, minor: 1)
        let headers = HTTPHeaders([("X-Test", "true")])
        var buffer = ByteBufferAllocator().buffer(capacity: 5)
        buffer.writeString("hello")
        let request = HTTPRequest(method: method, url: uri, version: version, headers: headers, body: .bytes(buffer))
        #expect(request.method == .GET)
        #expect(request.url.string == "https://localhost/api")
        #expect(request.url.path == "/api")
        #expect(request.version.major == 1)
        #expect(request.headers["X-Test"] == ["true"])
        #expect(try request.body?.bytes().get().readableBytes == 5)
    }

    @Test("描述字符串输出")
    func testDescription() {
        var buffer = ByteBufferAllocator().buffer(capacity: 5)
        buffer.writeString("world")
        let req = HTTPRequest(method: .PUT, url: WebURI(stringLiteral: "https://localhost/put"), headers: ["Content-Length": "5"], body: .bytes(buffer))
        let desc = req.description
        #expect(desc.contains("PUT /put HTTP/1.1"))
        #expect(desc.lowercased().contains("content-length: 5"))
        #expect(desc.contains("world"))
    }

    @Test("生成数据缓冲区")
    func testDataBuffer() throws {
        var buffer = ByteBufferAllocator().buffer(capacity: 0)
        buffer.writeString("abc123")
        let request = HTTPRequest(method: .PATCH, url: WebURI(stringLiteral: "https://localhost/patch"), body: .bytes(buffer))
        let headerBuffer = request.headData(allocator: .init())
        let bodyBuffer = try request.body?.bytes().get()
        let headerStr = headerBuffer.getString(at: 0, length: headerBuffer.readableBytes) ?? ""
        #expect(headerStr.contains("PATCH /patch HTTP/1.1"))
        #expect(headerStr.lowercased().contains("content-length"))
        #expect(bodyBuffer?.readableBytes == 6)
    }

    @Test("stream body 应该自动添加 Transfer-Encoding")
    func testStreamBodyHeaders() async throws {
        let stream = AsyncThrowingChannel<ByteBuffer, Error>()
        
        Task {
            await stream.send(ByteBuffer(string: "stream content"))
            stream.finish()
        }

        var request = HTTPRequest(
            method: .POST,
            url: WebURI(stringLiteral: "https://localhost/upload"),
            headers: ["X-Custom": "abc"]
        )
        request.body = HTTPBody(type: .stream(stream))

        #expect(request.headers["transfer-encoding"] == ["chunked"])
        #expect(request.headers["content-length"] == [])
        #expect(request.headers["X-Custom"] == ["abc"])
    }

    @Test("移除 body 应该清除相关头部")
    func testClearBody() throws {
        var buf = ByteBufferAllocator().buffer(capacity: 8)
        buf.writeString("bye bye")
        var request = HTTPRequest(method: .DELETE, url: "http://localhost:6500")
        request.body = HTTPBody(type: .bytes(buf), headers: ["x-body": "1"])

        #expect(request.headers["x-body"] == ["1"])
        #expect(request.headers["content-length"] == ["7"])

        request.body = nil

        #expect(request.headers["x-body"] == [])
        #expect(request.headers["content-length"] == ["0"])
        #expect(request.headers["transfer-encoding"] == [])
    }

    @Test("headData 生成正确的请求行和头部")
    func testHeadDataContent() throws {
        let req = HTTPRequest(
            method: .HEAD,
            url: WebURI(stringLiteral: "http://localhost:6500/check"),
            headers: ["Authorization": "Bearer token"]
        )
        let buf = req.headData()
        let str = buf.getString(at: 0, length: buf.readableBytes) ?? ""
        #expect(str.contains("HEAD /check HTTP/1.1"))
        #expect(str.contains("Authorization: Bearer token"))
        #expect(str.contains("\r\n\r\n"))
    }
}
