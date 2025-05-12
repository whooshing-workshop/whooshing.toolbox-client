import Vapor
import ErrorHandle
import DataConvertable
import NIOCore
import Logging
import Cryptos

final class APIReqClient: ReqClient, StorageKey, WhooshingClient, @unchecked Sendable {
    typealias Value = APIReqClient

    enum APIReqErr: String, ErrList {
        var domain: String { "woo.sys.api.reqclient.err" }
        case unknowSendError = "请求时发生未知的错误"
        case requestParaMissing = "请求参数缺失"
        case badResponse = "响应状态码表示请求未成功"
        case authenticationBadProtocol = "认证时协议协商错误"
        case parseParaFailed = "解析请求参数时失败"
    }

    static func new(eventLoop: EventLoop, logger: Logger? = nil, byteBufferAllocator: ByteBufferAllocator) -> Self {
        let res = Self(eventLoop: eventLoop, logger: logger, byteBufferAllocator: byteBufferAllocator)
        res.ioHandler = API.RequestIOCrypto(client: res, logger: logger)
        return res
    }
    
    func send(
        _ method: HTTPMethod,
        headers: HTTPHeaders,
        to url: URI,
        bufferStrategy: BufferStrategy,
        beforeSend: @escaping BeforeSendAction,
        afterSend: @escaping AsyncAfterSendAction,
        progress: @escaping ProgressAction
    ) -> EventLoopFuture<ClientResponse?> {
        let req = ClientRequest(method: method, url: url, headers: headers, body: nil, byteBufferAllocator: self.byteBufferAllocator)
        return self.makeChannel(url: req.url).flatMap { (channel, handler, domain) in
            do {
                var request = req
                try beforeSend(&request, channel)
                request.channel = channel
                if case .collect = bufferStrategy {
                    self.logger?.info("API.Client-发送请求: \(channel.clientAddrInfo)")
                } else {
                    self.logger?.info("API.Client-发送流式请求: \(channel.clientAddrInfo)")
                }
                return self._send(request: request, channel: channel, handler: handler, domain: domain, bufferStrategy: bufferStrategy, progress: progress).flatMapError { err in
                    return channel.eventLoop.makeFailedFuture(err)
                }.flatMap { res in
                    afterSend(channel).map { res }
                }
            } catch {
                return channel.eventLoop.makeFailedFuture(error)
            }
        }
    }

    struct JSONData: Content {
        let data: Data
    }
    
    private func _send(request: ClientRequest, channel: Channel, handler: RequestHandler, domain: String?, bufferStrategy: BufferStrategy, progress: @escaping @Sendable (ProgressContext<ClientResponse?>) throws -> Void) -> EventLoopFuture<ClientResponse?> {
        let id = ObjectIdentifier(channel)
        var r = eventLoop.makeSucceededVoidFuture()
        guard let ioData = self.apiRequestIoData else { return eventLoop.makeFailedFuture(APIReqErr.requestParaMissing.d("apiRequestIoData", 12013, (#file, #line))) }
        if ioData.connectionKeys[id] == nil {
            self.logger?.debug("正在与服务器进行认证: \(channel.clientAddrInfo)")
            r = r.flatMap { 
                self.authExchange(request: request, handler: handler, domain: domain, channel: channel)
            }
        }
        return r.flatMap{
            self.logger?.debug("正在与服务器发送具体的请求: \(channel.clientAddrInfo)")
            return self.send(request, channel: channel, handler: handler, bufferStrategy: bufferStrategy, progress: progress)
        }.flatMapError { err in 
            channel.eventLoop.makeFailedFuture(APIReqErr.unknowSendError.d(12012, (#file, #line)).subErr(err))
        }
    }

    struct AuthExchangeJSON: Content {
        let credential: Data
        let tokenEncrypted: Data
    }

    /// 发送用户凭据以及用户口令，其中用户凭据明文发送，口令则进行加密并哈希
    func authExchange(request: ClientRequest, handler: RequestHandler, domain: String?, channel: Channel) -> EventLoopFuture<Void> {
        do {
            let ioData = self.apiRequestIoData!
            let id = ObjectIdentifier(channel)
            guard let credential = Data(base64Encoded: ioData.credential) else { throw APIReqErr.parseParaFailed.d("用户凭据", 12007, (#file, #line)) }
            self.logger?.trace("API.Client-认证中: 使用用户口令加密用户口令本身")
            guard let token = Data(base64Encoded: ioData.token) else { throw APIReqErr.parseParaFailed.d("用户口令", 12008, (#file, #line)) }
            let tokenKey = Crypto.Symm.Key(data: token)
            let tokenEncrypted = try Crypto.Symm.encrypt(token, key: tokenKey)
            self.logger?.trace("API.Client-认证中: 将凭据和加密后的用户口令进行 json 编码")
            guard let body = try? JSONEncoder().encode(AuthExchangeJSON(credential: credential, tokenEncrypted: tokenEncrypted)) else { return eventLoop.makeFailedFuture(APIReqErr.unknowSendError.d("JSON 编码失败", 14001, (#file, #line))) }
            self.logger?.trace("API.Client-认证中: 发送用户凭据以及用户口令")
            var headers: HTTPHeaders = ["content-type": "application/json"]
            if let domain = domain {
                headers.replaceOrAdd(name: .host, value: domain)
            }
            return self.send(.init(method: .POST, url: request.url, headers: headers, body: .init(data: body)), channel: channel, handler: handler, bufferStrategy: .collect, progress: { _ in }).flatMapThrowing { res in
                // 此处一定有响应，因为 bufferStrategy 是 .collect
                let res = res!
                self.logger?.trace("API.Client-正在完成认证: 认证请求发送完成")
                guard res.status == .ok else { throw APIReqErr.badResponse.d(14002, (#file, #line)) }
                // 当向认证模块发送认证请求之后，应当得到一个使用用户口令加密的新密钥，并使用该新密钥进行后续的通讯加密
                self.logger?.trace("API.Client-正在完成认证: 解析服务器的新密钥")
                guard let token = Data(base64Encoded: ioData.token) else { throw APIReqErr.parseParaFailed.d("用户口令", 14003, (#file, #line)) }
                let tokenKey = Crypto.Symm.Key(data: token)
                self.logger?.trace("API.Client-正在完成认证: 获取对方发来的加密新密钥")
                let keyEncrypted = try res.content.decode(JSONData.self).data
                self.logger?.trace("API.Client-正在完成认证: 使用用户口令解密新密钥")
                let newKey: Crypto.Symm.Key = try Crypto.Symm.decrypt(keyEncrypted, key: tokenKey)
                self.logger?.trace("API.Client-正在完成认证: 注册该新密钥，用于将来的连线加密")
                ioData.connectionKeys[id] = newKey
            }
        } catch let err {
            return channel.eventLoop.makeFailedFuture(err)
        }
    }

    deinit {
        Task { [weak self] in
            await self?.closeAll()
        }
    }
}
