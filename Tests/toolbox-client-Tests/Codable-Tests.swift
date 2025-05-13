import Testing
@testable import WhooshingClient
import NIOHTTP1
import Foundation

@Suite("HTTPCodable Tests")
struct HTTPCodableTests {

    @Test("HTTPMethod 编解码")
    func testHTTPMethodCodable() throws {
        let method = HTTPMethod.POST
        let data = try JSONEncoder().encode(method)
        let decoded = try JSONDecoder().decode(HTTPMethod.self, from: data)
        #expect(decoded == method)
    }

    @Test("HTTPVersion 编解码")
    func testHTTPVersionCodable() throws {
        let version = HTTPVersion(major: 2, minor: 0)
        let data = try JSONEncoder().encode(version)
        let decoded = try JSONDecoder().decode(HTTPVersion.self, from: data)
        #expect(decoded == version)
    }

    @Test("HTTPResponseStatus 编解码")
    func testHTTPResponseStatusCodable() throws {
        let status = HTTPResponseStatus.notFound
        let data = try JSONEncoder().encode(status)
        let decoded = try JSONDecoder().decode(HTTPResponseStatus.self, from: data)
        #expect(decoded == status)
    }

    @Test("HTTPHeaders 编解码为数组格式")
    func testHTTPHeadersCodableArrayFormat() throws {
        var headers = HTTPHeaders()
        headers.add(name: "X-Key", value: "Value")
        headers.add(name: "Accept", value: "*/*")

        let data = try JSONEncoder().encode(headers)
        let decoded = try JSONDecoder().decode(HTTPHeaders.self, from: data)

        #expect(decoded.contains(name: "X-Key"))
        #expect(decoded["X-Key"] == ["Value"])
        #expect(decoded["Accept"] == ["*/*"])
    }

    @Test("HTTPHeaders 旧格式兼容：字典解码")
    func testHTTPHeadersOldFormatCompatibility() throws {
        let oldFormat = #"{"Content-Type":"application/json","Authorization":"token"}"#.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(HTTPHeaders.self, from: oldFormat)
        #expect(decoded["Content-Type"] == ["application/json"])
        #expect(decoded["Authorization"] == ["token"])
    }
}
