import Cryptos
import ErrorHandle
import DataConvertable
import NIOCore
import Logging
import NIOHTTP1
import Foundation
import AsyncHTTPClient

extension APIReqClient {
    var apiRequestIoData: API.RequestIOData? { self.storage[API.RequestIOData.self] }
}

enum API {
    final class RequestIOData: SendableStorage.Key, Sendable {
        typealias Value = RequestIOData
        let credential: String
        let token: String
        let connectionKeys: SendableDictionary<ObjectIdentifier, Crypto.Symm.Key> = .init()
        let readingBufferDatas: SendableDictionary<ObjectIdentifier, ByteBuffer> = .init()
        let errorTemps: SendableDictionary<ObjectIdentifier, HTTPResponseStatus> = .init()
        
        init(credential: String, token: String) {
            self.credential = credential
            self.token = token
        }
    }
    
    struct RequestIOCrypto: RequestCryptoIOHandler, Sendable {
        
        weak private(set) var client: APIReqClient?
        let logger: Logger?
        
        var isAvaliable: Bool { client?.apiRequestIoData != nil }
        
        /// 发送请求时，进行编码并加密
        func send(data: ByteBuffer, context: ChannelHandlerContext) -> EventLoopFuture<ByteBuffer> {
            guard data.readableBytes > 0 else { return context.eventLoop.makeSucceededFuture(data) }
            guard let ioData = client?.apiRequestIoData else { return context.eventLoop.makeFailedFuture(ApiClient.InternalErr.requestParaMissing.d("apiRequestIoData", 12006)) }
            let id = ObjectIdentifier(context.channel)
            do {
                let cipher: Data
                logger?.trace("API.Client.HTTP-发送请求，进行加密(key: \(ioData.connectionKeys[id] != nil)) in \(context.channel.clientAddrInfo)")
                if let key = ioData.connectionKeys[id] {
                    cipher = try Crypto.Symm.encrypt(data, key: key)
                } else {
                    // 代表首次请求，直接发送明文
                    // 用户凭据可明文发送，且用户口令会加密处理，因此整个请求无需加密
                    cipher = .init(buffer: data)
                }
                let buffer = ByteBuffer(data: cipher)
                return context.eventLoop.makeSucceededFuture(buffer)
            } catch let err {
                return context.eventLoop.makeFailedFuture(err)
            }
        }

        /// 收到响应时，进行解密并解码
        func get(data: ByteBuffer, context: ChannelHandlerContext) -> EventLoopFuture<ByteBuffer> {
            guard data.readableBytes > 0 else { return context.eventLoop.makeSucceededFuture(data) }
            guard let ioData = client?.apiRequestIoData else { return context.eventLoop.makeFailedFuture(ApiClient.InternalErr.requestParaMissing.d("apiRequestIoData", 12010)) }
            let id = ObjectIdentifier(context.channel)

            // 检查对方回复的是不是一个未加密的 http 回复，如果是，则表示对方出错

            if let _ = ioData.errorTemps[id] {
                let err = parseError(body: data)
                ioData.errorTemps[id] = nil
                return context.eventLoop.makeFailedFuture(err)
            } else {
                if let status = lightweightParseHTTP1StatusCode(from: data) {
                    ioData.errorTemps[id] = status
                    return context.eventLoop.makeSucceededFuture(data)
                }
            }

            do {
                logger?.trace("API.Client.HTTP-收到响应，进行解密(key: \(ioData.connectionKeys[id] != nil)) in \(context.channel.clientAddrInfo)")
                var plain: ByteBuffer
                if let key = ioData.connectionKeys[id] {
                    plain = try Crypto.Symm.decrypt(.init(buffer: data), key: key)
                } else {
                    guard let token = Data(base64Encoded: ioData.token) else { throw ApiClient.Err.parseParaFailed.d("用户口令", 14005).adds(.internalServerError) }
                    let tokenKey = Crypto.Symm.Key(data: token)
                    plain = try Crypto.Symm.decrypt(.init(buffer: data), key: tokenKey)
                }
                return context.eventLoop.makeSucceededFuture(plain)
            } catch let err {
                return context.eventLoop.makeFailedFuture(err)
            }
        }

        // 检查 response 是否为 HTTP 格式的头，如果是，则返回其状态码
        func checkHeader(res: ByteBuffer) -> HTTPResponseStatus? {
            do {
                let res = try String(data: res.data())
                let lines = res.split(separator: "\r\n")
                let fields = lines[0].split(separator: " ")
                if fields.count >= 3, let code = Int(fields[1]) {
                    return .init(statusCode: code)
                }
            } catch { }
            return nil
        }

        // 检查 response 是否为 HTTP 格式且包括错误状态码
        func parseError(body: ByteBuffer) -> Error {
            struct BodyReply: Codable {
                let error: Bool
                let reason: String
            }
            do {
                let reply = try Guard({ try JSONDecoder().decode(BodyReply.self, from: Data(buffer: body)) }, throw: ApiClient.InternalErr.protocolInvalid.d("应当解析出 Error 信息，但失败", 14012))
                if reply.error {
                    return ApiClient.Err.unknowError.d(reply.reason, 13001).adds(.internalServerError)
                } else {
                    throw ApiClient.InternalErr.protocolInvalid.d("应当解析出 Error 信息，但失败", 14011)
                }
            } catch let err {
                return err
            }
        }

        // 连线建立
        func connectionStart(context: ChannelHandlerContext) -> EventLoopFuture<Void> {
            logger?.debug("API.Client-连线建立: \(context.channel.clientAddrInfo)")
            return context.eventLoop.makeSucceededVoidFuture()
        }

        // 连线结束，进行清理
        func connectionEnd(context: ChannelHandlerContext) -> EventLoopFuture<Void> {
            logger?.debug("API.Client-连线结束: \(context.channel.clientAddrInfo)")
            let id = ObjectIdentifier(context.channel)
            client?.apiRequestIoData?.connectionKeys[id] = nil
            client?.apiRequestIoData?.readingBufferDatas[id] = nil
            return context.eventLoop.makeSucceededVoidFuture()
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
