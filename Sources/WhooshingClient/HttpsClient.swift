import Cryptos
import AsyncAlgorithms
import ErrorHandle
import NIOConcurrencyHelpers
import NIO
import Logging
import NIOHTTP1
import AsyncHTTPClient
import Foundation

public final class HttpsClient: WhooshingClient, @unchecked Sendable {
    
    public enum Err: String, ErrList {
        public var domain: String { "woo.sys.httpsclient.err" }
        case streamingEngageFailed = "流传输数据获取失败"
        case urlConnectionFailed = "对该 url 目标地址连接失败"
        case responseNotValid = "对方响应不合法"
    }
    
    public var key: Cryptos.Crypto.Symm.Key? { fatalError("永远不应调用此属性") }
    public var channel: (any NIOCore.Channel)? { fatalError("永远不应调用此属性") }
    public var fileEventLoop: any NIOCore.EventLoop
    public let logger: Logger?
    private let client: HTTPClient
    
    public init(in eventLoop: EventLoop, configuration: HTTPClient.Configuration = .singletonConfiguration, logger: Logger? = nil) {
        self.fileEventLoop = eventLoop
        self.logger = logger
        self.client = HTTPClient(eventLoopGroup: eventLoop, configuration: configuration)
    }
    
    public func send(
        _ request: HTTPRequest
    ) -> EventLoopFuture<HTTPResponse> {
        fileEventLoop.makeFutureWithTask { try await self.streamingSend(request) }
    }
    
    deinit {
        try? self.client.syncShutdown()
    }
    
    public func removeHTTPHandlers(in eventLoop: any NIOCore.EventLoop) -> NIOCore.EventLoopFuture<Void> {
        eventLoop.makeSucceededVoidFuture()
    }
    
    public func removeHTTPHandlers() async throws { return }
}

extension HttpsClient {
    private func streamingSend(
        _ request: HTTPRequest
    ) async throws -> HTTPResponse {
        var req = HTTPClientRequest(url: request.url.string)
        req.method = request.method
        req.headers = request.headers
        
        try await Curl.isUriConnectable(request.url.string)
        
        if let body = request.body {
            switch body.type {
            case .bytes(let bytes): req.body = .bytes(bytes)
            case .stream(let stream): req.body = .stream(stream, length: .unknown)
            }
        }
        self.logger?.info("HTTPS.Client-发送请求: \(request.url)")
        let response = try await client.execute(req, deadline: .distantFuture, logger: logger)
        
        var res = HTTPResponse(status: response.status, version: response.version, headers: response.headers)
        
        for h in response.headers {
            if h.name == "content-length" {
                guard let bodySize = Int(h.value) else {
                    throw Err.responseNotValid.d("content-type 头大小解析失败", 15004)
                }
                res.body = .bytes(try await response.body.collect(upTo: bodySize))
                return res
            } else if h.name == "transfer-encoding" && h.value.lowercased() == "chunked" {
                let stream = AsyncThrowingChannel<ByteBuffer, Error>()
                // 异步收集流数据
                Task {
                    do {
                        for try await chunk in response.body {
                            await stream.send(chunk)
                        }
                        stream.finish()
                    } catch {
                        stream.fail(error)
                    }
                }
                res.body = .stream(stream)
                return res
            }
        }
        throw Err.responseNotValid.d("未找到 content-type 或 transfer-encoding 头", 15005)
    }
}
