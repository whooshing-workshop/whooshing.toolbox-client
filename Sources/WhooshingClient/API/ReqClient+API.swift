import NIOAdvanced
import Cryptos
import NIOHTTP1
import Foundation
import AsyncHTTPClient
import LoggingAdvanced

@usableFromInline
final class APIReqClient: ReqClient<API.RequestIOCrypto>, SendableStorage.Key, @unchecked Sendable {
    @usableFromInline
    typealias Value = APIReqClient
    @usableFromInline
    typealias Errcase = ApiClient.Errcase
    @usableFromInline
    typealias Failure = ApiClient.Failure

    @inlinable
    static func new(eventLoop: EventLoop, logger: Logger? = nil, byteBufferAllocator: ByteBufferAllocator) -> Self {
        let res = Self(eventLoop: eventLoop, logger: logger, byteBufferAllocator: byteBufferAllocator)
        res.ioHandler = API.RequestIOCrypto(client: res)
        return res
    }
    
    @inlinable
    func send(
        _ request: HTTPRequest
    ) -> EventLoopResult<HTTPResponse, Failure> {
        self.makeChannel(url: request.url)
            .errCast(Errcase.tcpChannelAssignFailed)
            .flatMap
        { channel, handler, domain in
            self.logger?.info("API.Client-发送请求", metadata: ["client_addr": .string(channel.clientAddrInfo)])
            self.logger?.debug("请求内容", metadata: ["request": .data(request)])
            return self._send(request: request, channel: channel, handler: handler, domain: domain).map { res in
                self.logger?.info("发送请求成功，收到响应", metadata: ["status": .stringConvertible(res.status)])
                self.logger?.debug("响应内容", metadata: ["response": .data(res)])
                return res
            }
        }.logIfFailAndExist(logger: self.logger)
    }

    struct JSONData: Codable {
        let data: Data
    }
    
    @usableFromInline
    func _send(
        request: HTTPRequest,
        channel: Channel,
        handler: RequestWrapperHandler,
        domain: String?
    ) -> EventLoopResult<HTTPResponse, Failure> {
        let id = ObjectIdentifier(channel)
        var r = eventLoop.makeSucceededVoidResult(throws: Failure.self)
        guard let ioData = self.apiRequestIoData else {
            return eventLoop.makeFailedResult(Errcase.internalFailure, "请求参数缺失: apiRequestIoData")
        }
        if ioData.connectionKeys[id] == nil {
            self.logger?.debug("正在与服务器进行认证", metadata: ["client_addr": .string(channel.clientAddrInfo)])
            r = r.flatMap {
                self.authExchange(request: request, handler: handler, domain: domain, channel: channel)
            }
        }
        return r.flatMap{
            self.logger?.debug("正在与服务器发送具体的请求", metadata: ["client_addr": .string(channel.clientAddrInfo), "request": .data(request)])
            return self.send(request, channel: channel, handler: handler).errCast(Errcase.tcpSendFailed, "发送用户请求失败")
        }
    }

    struct AuthExchangeJSON: Encodable {
        let credential: Data
        let tokenEncrypted: Data
    }

    /// 发送用户凭据以及用户口令，其中用户凭据明文发送，口令则进行加密并哈希
    func authExchange(
        request: HTTPRequest,
        handler: RequestWrapperHandler,
        domain: String?,
        channel: Channel
    ) -> EventLoopResult<Void, Failure> {
        channel.eventLoop.submitResult { () throws(Failure) in
            guard let ioData = self.apiRequestIoData else {
                throw Errcase.internalFailure.d("apiRequestIoData 参数未找到")
            }
            
            self.logger?.debug("取得 ioData", metadata: ["io_data": .data(ioData)])
            
            guard let credential = Data(base64Encoded: ioData.credential) else {
                throw Errcase.badRequest.d("解析请求中的 用户凭据 数据失败")
            }
            
            self.logger?.debug("API.Client-认证中: 使用用户口令加密用户口令本身")
            guard let token = Data(base64Encoded: ioData.token) else {
                throw Errcase.badRequest.d("解析请求中的 用户口令 数据失败")
            }
            
            let tokenKey = Crypto.Symm.Key(data: token)
            let tokenEncrypted = try required(throws: Errcase.encryptFailed) {
                try Crypto.Symm.encrypt(token, key: tokenKey).get()
            }
            
            self.logger?.debug("API.Client-认证中: 将凭据和加密后的用户口令进行 json 编码")
            let body = try required(throws: Errcase.jsonEncodeFailed) {
                try HTTPBody.json(AuthExchangeJSON(credential: credential, tokenEncrypted: tokenEncrypted)).get()
            }
            
            self.logger?.debug("API.Client-认证中: 发送用户凭据以及用户口令")
            var headers: HTTPHeaders = ["content-type": "application/json"]
            if let domain = domain {
                headers.replaceOrAdd(name: "host", value: domain)
            }
            
            return (
                ioData,
                HTTPRequest(
                    method: .POST,
                    url: request.url,
                    headers: headers,
                    body: body
                )
            )
        }.flatMap { (ioData: API.RequestIOData, req) in
            self.send(req, channel: channel, handler: handler).errCast(Errcase.tcpSendFailed).map { (ioData, $0) }
        }.flatMapThrowing { ioData, res throws(Failure) in
            self.logger?.debug("API.Client-正在完成认证: 认证请求发送完成", metadata: ["result": .data(res)])
            guard res.status == .ok else {
                throw Errcase.badResponse.d().metadata(["status": .stringConvertible(res.status)])
            }
            
            guard let resBody = res.body else {
                throw Errcase.badResponse.d("响应体为空")
            }
            
            // 当向认证模块发送认证请求之后，应当得到一个使用用户口令加密的新密钥，并使用该新密钥进行后续的通讯加密
            self.logger?.debug("API.Client-正在完成认证: 解析服务器的新密钥")
            guard let token = Data(base64Encoded: ioData.token) else {
                throw Errcase.badResponse.d("未解析得到用户口令")
            }
            let tokenKey = Crypto.Symm.Key(data: token)
            
            self.logger?.debug("API.Client-正在完成认证: 获取对方发来的加密新密钥")
            let keyEncrypted = try required(throws: Errcase.jsonDecodeFailed) {
                try resBody.json(as: JSONData.self).get().data
            }
            
            self.logger?.debug("API.Client-正在完成认证: 使用用户口令解密新密钥")
            let newKey: SendableSymmKey = try required(throws: Errcase.decryptFailed) {
                try Crypto.Symm.decrypt(keyEncrypted, key: tokenKey).get()
            }
            
            let id = ObjectIdentifier(channel)
            
            self.logger?.debug("API.Client-正在完成认证: 注册该新密钥，用于将来的连线加密")
            ioData.connectionKeys[id] = newKey
        }
    }

    deinit {
        Task { [weak self] in
            await self?.closeAll()
        }
    }
}
