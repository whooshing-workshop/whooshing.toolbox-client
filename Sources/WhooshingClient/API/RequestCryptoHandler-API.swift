import Cryptos
import ErrorHandle
import DataConvertable
import NIOCore
import NIOHTTP1
import NIOAdvanced
import Logging
import Foundation
import AsyncHTTPClient
import NIOFoundationCompat

extension APIReqClient {
    @inlinable
    var apiRequestIoData: API.RequestIOData? { self.storage[API.RequestIOData.self] }
}

@usableFromInline
enum API {
    @frozen
    public enum Errcase: String, ErrList {
        case requestEncryptFailed = "请求数据加密时失败"
        case responseDecryptFailed = "响应数据解密时失败"
        case responseParseErrorFailed = "从响应数据解析错误信息时失败"
        case parseResponseFailed = "解析响应数据时失败"
        
        case internalFailure = "内部错误"
    }
    
    @usableFromInline
    final class RequestIOData: SendableStorage.Key, Sendable {
        @usableFromInline
        typealias Value = RequestIOData
        @usableFromInline
        let credential: String
        @usableFromInline
        let token: String
        @usableFromInline
        let connectionKeys: SendableDictionary<ObjectIdentifier, Crypto.Symm.Key> = .init()
        @usableFromInline
        let readingBufferDatas: SendableDictionary<ObjectIdentifier, ByteBuffer> = .init()
        @usableFromInline
        let errorTemps: SendableDictionary<ObjectIdentifier, HTTPResponseStatus> = .init()
        
        @usableFromInline
        init(credential: String, token: String) {
            self.credential = credential
            self.token = token
        }
    }
    
    @usableFromInline
    struct RequestIOCrypto: RequestCryptoIOHandler, Sendable {
        
        @usableFromInline
        typealias Failure = Errcase.ErrType
        
        @usableFromInline
        weak private(set) var client: APIReqClient?
        @usableFromInline
        let logger: Logger?
        
        @inlinable
        var isAvaliable: Bool { client?.apiRequestIoData != nil }
        
        @inlinable
        init(client: APIReqClient? = nil, logger: Logger?) {
            self.client = client
            self.logger = logger
        }
        
        /// 发送请求时，进行编码并加密
        @usableFromInline
        func send(data: ByteBuffer, context: ChannelHandlerContext) -> EventLoopRes<ByteBuffer, Errcase> {
            guard data.readableBytes > 0 else { return context.eventLoop.makeSucceededResult(data) }
            guard let ioData = client?.apiRequestIoData else { return context.eventLoop.makeFailedResult(Errcase.internalFailure.d("apiRequestIoData")) }
            let id = ObjectIdentifier(context.channel)
            do {
                let cipher: Data
                logger?.trace("API.Client.HTTP-发送请求，进行加密(key: \(ioData.connectionKeys[id] != nil)) in \(context.channel.clientAddrInfo)")
                if let key = ioData.connectionKeys[id] {
                    cipher = try required(throws: Errcase.requestEncryptFailed) {
                        try Crypto.Symm.encrypt(data, key: key).get()
                    }
                } else {
                    // 代表首次请求，直接发送明文
                    // 用户凭据可明文发送，且用户口令会加密处理，因此整个请求无需加密
                    cipher = .init(buffer: data)
                }
                let buffer = ByteBuffer(data: cipher)
                return context.eventLoop.makeSucceededResult(buffer)
            } catch let err {
                return context.eventLoop.makeFailedResult(err)
            }
        }

        /// 收到响应时，进行解密并解码
        @usableFromInline
        func get(data: ByteBuffer, context: ChannelHandlerContext) -> EventLoopRes<ByteBuffer, Errcase> {
            guard data.readableBytes > 0 else { return context.eventLoop.makeSucceededResult(data) }
            guard let ioData = client?.apiRequestIoData else { return context.eventLoop.makeFailedResult(Errcase.internalFailure.d("apiRequestIoData")) }
            let id = ObjectIdentifier(context.channel)

            // 检查对方回复的是不是一个未加密的 http 回复，如果是，则表示对方出错

            if let _ = ioData.errorTemps[id] {
                // 如果错误已经存在了，则直接报错
                let err = parseError(body: data)
                ioData.errorTemps[id] = nil
                return context.eventLoop.makeFailedResult(err)
            } else {
                // 错误不存在，从对方的相应中尝试解析出错误
                if let status = lightweightParseHTTP1StatusCode(from: data) {
                    ioData.errorTemps[id] = status
                    return context.eventLoop.makeSucceededResult(data)
                }
            }
            
            return context.eventLoop.makeResultWithTask { () throws(Errcase.ErrType) in
                logger?.trace("API.Client.HTTP-收到响应，进行解密(key: \(ioData.connectionKeys[id] != nil)) in \(context.channel.clientAddrInfo)")
                var plain: ByteBuffer
                if let key = ioData.connectionKeys[id] {
                    plain = try required(throws: Errcase.responseDecryptFailed) {
                        try Crypto.Symm.decrypt(.init(buffer: data), key: key).get()
                    }
                } else {
                    guard let token = Data(base64Encoded: ioData.token) else {
                        throw Errcase.parseResponseFailed.d("用户口令")
                    }
                    let tokenKey = Crypto.Symm.Key(data: token)
                    plain = try required(throws: Errcase.responseDecryptFailed) {
                        try Crypto.Symm.decrypt(.init(buffer: data), key: tokenKey).get()
                    }
                }
                return plain
            }
        }
        
        // 连线建立
        @usableFromInline
        func connectionStart(context: ChannelHandlerContext) -> EventLoopRes<Void, Errcase> {
            logger?.debug("API.Client-连线建立: \(context.channel.clientAddrInfo)")
            return context.eventLoop.makeSucceededVoidResult()
        }

        // 连线结束，进行清理
        @usableFromInline
        func connectionEnd(context: ChannelHandlerContext) -> EventLoopRes<Void, Errcase> {
            logger?.debug("API.Client-连线结束: \(context.channel.clientAddrInfo)")
            let id = ObjectIdentifier(context.channel)
            client?.apiRequestIoData?.connectionKeys[id] = nil
            client?.apiRequestIoData?.readingBufferDatas[id] = nil
            return context.eventLoop.makeSucceededVoidResult()
        }

        // 检查 response 是否为 HTTP 格式的头，如果是，则返回其状态码
        func checkHeader(res: ByteBuffer) -> HTTPResponseStatus? {
            guard let res = try? String.make(data: res.data).get() else {
                return nil
            }
            let lines = res.split(separator: "\r\n")
            let fields = lines[0].split(separator: " ")
            if fields.count >= 3, let code = Int(fields[1]) {
                return .init(statusCode: code)
            }
            
            return nil
        }

        struct BodyReply: Codable {
            @usableFromInline
            let error: Bool
            @usableFromInline
            let reason: String
        }
        
        // 检查 response 是否为 HTTP 格式且包括错误状态码
        func parseError(body: ByteBuffer) -> Errcase.ErrType {
            let reply: BodyReply
            do {
                reply = try required(throws: Errcase.responseParseErrorFailed, "应当解析出 Error 信息") {
                    try JSONDecoder().decode(BodyReply.self, from: Data(buffer: body))
                }
            } catch let err {
                return err
            }
                
            if reply.error {
                return Errcase.internalFailure.d(reply.reason)
            } else {
                return Errcase.responseParseErrorFailed.d("应当解析出 Error 信息，但失败")
            }
        }
        
        func lightweightParseHTTP1StatusCode(from buffer: ByteBuffer) -> HTTPResponseStatus? {
            // 确保至少有 "HTTP/1.1 200" 这段内容（12 字节）
            guard buffer.readableBytes >= 12 else {
                return nil
            }

            // 获取前 9 个字节，应该是 "HTTP/1.1 "
            let expectedPrefix = "HTTP/1.1 "
            let prefixBytes = buffer.getBytes(at: buffer.readerIndex, length: 9)

            guard let actual = prefixBytes, actual == Array(expectedPrefix.utf8) else { return nil }

            // 接下来是状态码 3 字节
            let statusStart = buffer.readerIndex + 9
            guard
                let codeStr = buffer.getString(at: statusStart, length: 3),
                let code = Int(codeStr)
            else {
                return nil
            }

            return .init(statusCode: code)
        }
    }
}
