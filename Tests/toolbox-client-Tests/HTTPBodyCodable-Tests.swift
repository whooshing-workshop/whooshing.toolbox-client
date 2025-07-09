import Testing
import AsyncAlgorithms
import NIOCore
import Foundation
@testable import WhooshingClient

struct Example: Codable, Equatable {
    let name: String
    let value: Int
}

@Suite("HTTPBody 编解码测试")
struct HTTPBodyCodableTests {
    @Test("Throwable Data 类型支持编码和解码")
    func testDataEncodeDecode() throws {
        let original = "Hello World!"
        let data = original.data(using: .utf8)!
        let body = HTTPBody.data(data)
        let decodedData: Data = try body.data().get()
        let decoded = try String.make(data: decodedData).get()
        #expect(decoded == original)
        let contentType = try #require(body.headers.first(name: "content-type"))
        #expect(contentType == "application/octet-stream")
    }

    @Test("纯文本类型支持编码和解码")
    func testTextEncodeDecode() throws {
        let input = "Hello Testing"
        let body = try HTTPBody.text(input).get()
        let output: String = try body.data().get()
        #expect(output == input)
        let contentType = try #require(body.headers.first(name: "content-type"))
        #expect(contentType == "text/plain")
    }

    @Test("JSON 类型支持编码和解码")
    func testJSONEncodeDecode() throws {
        let obj = Example(name: "json", value: 7)
        let body = try HTTPBody.json(obj).get()
        let decoded: Example = try body.json().get()
        #expect(decoded == obj)
        let contentType = try #require(body.headers.first(name: "content-type"))
        #expect(contentType == "application/json")
    }

    @Test("Stream 类型支持编码和异步解码")
    func testStreamEncodeDecode() async throws {
        let values = [Example(name: "a", value: 1), Example(name: "b", value: 2)]
        let stream = AsyncThrowingChannel<Example, Error>()
        Task {
            for value in values {
                await stream.send(value)
            }
            stream.finish()
        }
        let body = HTTPBody.jsonStream(stream)
        var decoded: [Example] = []
        for try await item in try body.jsonStream(as: Example.self).get() {
            decoded.append(item)
        }
        #expect(decoded == values)
        let contentType = try #require(body.headers.first(name: "content-type"))
        #expect(contentType == "application/octet-stream")
    }
}
