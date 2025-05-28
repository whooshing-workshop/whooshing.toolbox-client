import Testing
import AsyncAlgorithms
@testable import WhooshingClient
import NIOHTTP1
import NIOCore
import Foundation

#if WHOOSHING_VAPOR
import Vapor
#endif

extension String: @retroactive Error {}

@Suite("HTTPResponse Tests")
struct HTTPResponseTests {
    
    struct Payload: Codable, Equatable {
        let message: String
    }

    @Test("初始化 HTTPResponse")
    func testInit() throws {
        let version = HTTPVersion(major: 1, minor: 1)
        let status = HTTPResponseStatus.ok
        let headers = HTTPHeaders([("Content-Type", "text/plain")])
        var buffer = ByteBufferAllocator().buffer(capacity: 5)
        buffer.writeString("hello")
        let response = HTTPResponse(status: status, body: .bytes(buffer), version: version, headers: headers)
        #expect(response.version.major == 1)
        #expect(response.status == .ok)
        #expect(response.headers.contains(name: "content-type"))
        #expect(try response.body?.bytes().readableBytes == 5)
    }

    @Test("description 输出应包含头部和主体")
    func testDescription() {
        var buffer = ByteBufferAllocator().buffer(capacity: 5)
        buffer.writeString("world")
        let response = HTTPResponse(status: .notFound, body: .bytes(buffer), version: .http1_1, headers: ["X-Header": "val"])
        let desc = response.description
        #expect(desc.contains("HTTP/1.1 404 Not Found"))
        #expect(desc.contains("X-Header: val"))
        #expect(desc.contains("world"))
    }
    
    @Test("HTTPResponse 应当设置正确的 content-length")
    func testHTTPResponseBytesBodyHeaders() throws {
        var buffer = ByteBufferAllocator().buffer(capacity: 64)
        buffer.writeString("Hello Bytes")
        let body = HTTPBody(type: .bytes(buffer))
        var response = HTTPResponse(status: .ok)
        response.body = body

        #expect(response.headers.first(name: "content-length") == "11")
        #expect(response.headers.contains(name: "transfer-encoding") == false)
    }

    @Test("HTTPResponse 空响应体应当移除 content headers")
    func testHTTPResponseNilBodyClearsHeaders() throws {
        var buffer = ByteBufferAllocator().buffer(capacity: 64)
        buffer.writeString("Temp Body")
        let initialBody = HTTPBody(type: .bytes(buffer), headers: ["x-temp-header": "value"])
        var response = HTTPResponse(status: .ok)
        response.body = initialBody

        #expect(response.headers.contains(name: "x-temp-header"))

        response.body = nil

        #expect(response.headers.contains(name: "x-temp-header") == false)
        #expect(response.headers.contains(name: "content-length"))
        #expect(response.headers.first(name: "content-length") == "0")
        #expect(response.headers.contains(name: "transfer-encoding") == false)
    }

    @Test("HTTPResponse description includes status and body string")
    func testHTTPResponseDescription() throws {
        var buffer = ByteBufferAllocator().buffer(capacity: 64)
        buffer.writeString("Description Test")
        let body = HTTPBody(type: .bytes(buffer))
        let response = HTTPResponse(status: .notFound, body: body)

        let desc = response.description
        #expect(desc.contains("404 Not Found"))
        #expect(desc.contains("Description Test"))
    }

    @Test("HTTPResponse stream body includes custom headers")
    func testHTTPResponseStreamBodyWithHeaders() async throws {
        let buffer = ByteBuffer(string: "data")
        let stream = AsyncThrowingChannel<ByteBuffer, Error>()
        
        Task {
            await stream.send(buffer)
            stream.finish()
        }

        let body = HTTPBody(type: .stream(stream), headers: ["x-stream": "true"])
        var response = HTTPResponse(status: .ok)
        response.body = body

        #expect(response.headers.first(name: "transfer-encoding") == "chunked")
        #expect(response.headers.first(name: "x-stream") == "true")
    }

    #if WHOOSHING_VAPOR
    @Test("Vapor ResponseEncodable / AsyncResponseEncodable")
    func testVaporEncodeResponse() async throws {
        let app = try await Application.make(.testing)

        var buffer = ByteBufferAllocator().buffer(capacity: 0)
        buffer.writeString("test body")

        let original = HTTPResponse(
            status: .created,
            body: .bytes(buffer),
            version: .http1_1,
            headers: ["X-Test": "yes"]
        )

        let res1 = try await original.encodeResponse(for: Request(application: app, on: app.eventLoopGroup.next())).get()
        #expect(res1.status == .created)
        #expect(res1.headers["X-Test"] == ["yes"])
        let string1 = res1.body.string
        #expect(string1 == "test body")

        let res2 = try await original.encodeResponse(for: Request(application: app, on: app.eventLoopGroup.next())).get()
        let string2 = res2.body.string
        #expect(string2 == "test body")
        
        try await app.asyncShutdown()
    }
    #endif
}
