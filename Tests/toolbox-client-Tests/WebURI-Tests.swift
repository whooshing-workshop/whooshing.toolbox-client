import Testing
@testable import WhooshingClient
import Foundation

@Suite("WebURI Tests")
struct WebURITests {

    @Test("通过 stringLiteral 初始化完整 URI")
    func testStringLiteralInit() {
        let uri: WebURI = "https://example.com:8443/path?foo=bar#frag"
        #expect(uri.scheme == .https)
        #expect(uri.host == "example.com")
        #expect(uri.port == 8443)
        #expect(uri.path == "/path")
        #expect(uri.query == "foo=bar")
        #expect(uri.fragment == "frag")
        #expect(uri.string == "https://example.com:8443/path?foo=bar#frag")
    }
    
    @Test("stringLiteral 转义测试")
    func literalQueryTest() {
        let uri: WebURI = "https://example.com:8443/path testing?foo=hello world!&name=chenlin wang#frag testing"
        #expect(uri.scheme == .https)
        #expect(uri.host == "example.com")
        #expect(uri.port == 8443)
        #expect(uri.path == "/path testing")
        #expect(uri.query == "foo=hello world!&name=chenlin wang")
        #expect(uri.fragment == "frag testing")
        #expect(uri.string == "https://example.com:8443/path%20testing?foo=hello%20world!&name=chenlin%20wang#frag%20testing")
    }

    @Test("使用 URL 字符串初始化失败")
    func testInvalidURLInit() {
        #expect(throws: Error.self, performing: { try WebURI(string: "not a valid url") })
    }

    @Test("使用参数构造 URI")
    func testInitWithComponents() {
        let uri = WebURI(
            scheme: .http,
            host: "host.test",
            port: 1234,
            path: "/api",
            query: ["k1": "v1", "k2": "v2"],
            fragment: "footer"
        )
        #expect(uri.scheme == .http)
        #expect(uri.host == "host.test")
        #expect(uri.port == 1234)
        #expect(uri.path == "/api")
        #expect(uri.query?.contains("k1=v1") == true)
        #expect(uri.query?.contains("k2=v2") == true)
        #expect(uri.fragment == "footer")
        #expect(uri.string.contains("http://host.test:1234/api") == true)
        #expect(uri.string.contains("?") == true)
        #expect(uri.string.contains("#footer") == true)
    }
    
    @Test("使用参数构造 URI 转义测试")
    func testInitWithComponentsQueryTest() {
        let uri = WebURI(
            scheme: .http,
            host: "host.test",
            port: 1234,
            path: "/api testing",
            query: ["k1 array": "v1 v2 v3", "k2 array": "v2 v4 v6"],
            fragment: "footer testing"
        )
        #expect(uri.scheme == .http)
        #expect(uri.host == "host.test")
        #expect(uri.port == 1234)
        #expect(uri.path == "/api testing")
        #expect(uri.query?.contains("k1 array=v1 v2 v3") == true)
        #expect(uri.query?.contains("k2 array=v2 v4 v6") == true)
        #expect(uri.fragment == "footer testing")
        #expect(uri.string.contains("http://host.test:1234/api%20testing") == true)
        #expect(uri.string.contains("k1%20array=v1%20v2%20v3") == true)
        #expect(uri.string.contains("k2%20array=v2%20v4%20v6") == true)
        #expect(uri.string.contains("?") == true)
        #expect(uri.string.contains("#footer%20testing") == true)
    }

    @Test("空 path 应默认变为 /")
    func testEmptyPathDefaultsToSlash() {
        let uri = WebURI(scheme: .https, host: "abc.com", path: "")
        #expect(uri.path == "/")
    }
    
    @Test("默认 path 应为 /")
    func testDefaultPathDefaultsToSlash() {
        let uri = WebURI(scheme: .https, host: "abc.com")
        #expect(uri.path == "/")
    }

    @Test("只提供 host 的简洁构造")
    func testOnlyHost() {
        let uri = WebURI(scheme: .http, host: "localhost")
        #expect(uri.path == "/")
        #expect(uri.port == nil)
        #expect(uri.query == nil)
        #expect(uri.fragment == nil)
    }

    @Test("域名识别 isDomainHost")
    func testIsDomainHost() {
        let domain = WebURI(scheme: .http, host: "example.com")
        let ip = WebURI(scheme: .http, host: "127.0.0.1")
        let localhost = WebURI(scheme: .http, host: "localhost")
        #expect(domain.isDomainHost() == true)
        #expect(ip.isDomainHost() == false)
        #expect(localhost.isDomainHost() == false)
    }

    @Test("Codable 编解码")
    func testCodable() throws {
        let original = WebURI(
            scheme: .https,
            host: "site.org",
            port: 443,
            path: "/p",
            query: ["a": "b"],
            fragment: "sec"
        )
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(WebURI.self, from: data)
        #expect(decoded.scheme == original.scheme)
        #expect(decoded.host == original.host)
        #expect(decoded.port == original.port)
        #expect(decoded.path == original.path)
        #expect(decoded.query == original.query)
        #expect(decoded.fragment == original.fragment)
        #expect(decoded.string == original.string)
    }
}
