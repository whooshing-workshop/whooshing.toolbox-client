import Vapor
import Cryptos
import ErrorHandle
import DataConvertable
import NIO
import Logging

extension APIReqClient {
    var apiRequestIoData: API.RequestIOData? { self.storage[API.RequestIOData.self] }
}

public enum API {
    final class RequestIOData: StorageKey, Sendable {
        typealias Value = RequestIOData
        let credential: String
        let token: String
        let connectionKeys: SendableDictionary<ObjectIdentifier, Crypto.Symm.Key> = .init()
        let readingBufferDatas: SendableDictionary<ObjectIdentifier, ByteBuffer> = .init()
        let errorTemps: SendableDictionary<ObjectIdentifier, HTTPStatus> = .init()
        
        init(credential: String, token: String) {
            self.credential = credential
            self.token = token
        }
    }
    
    enum Err: String, ErrList {
        var domain: String { "woo.sys.api.reqclient.err" }
        case requestParaMissing = "请求参数缺失"
        case parseParaFailed = "解析请求参数时失败"
        case internalError = "目标服务器发生错误"
        case protocolInvalid = "交接机制发生错误"
    }
    
    struct RequestIOCrypto: RequestIOHandler, Sendable {
        unowned private(set) var client: APIReqClient
        let logger: Logger?
        
        /// 发送请求时，进行编码并加密
        func send(request: ClientRequest, dataChunk: ByteBuffer, context: ChannelHandlerContext, allocator: ByteBufferAllocator, streaming: Bool) -> EventLoopFuture<ByteBuffer> {
            guard let ioData = client.apiRequestIoData else { return context.eventLoop.makeFailedFuture(Err.requestParaMissing.d("apiRequestIoData", 12006, (#file, #line))) }
            let id = ObjectIdentifier(context.channel)
            do {
                let cipher: Data
                logger?.trace("API.Client.HTTP-发送请求，进行加密(key: \(ioData.connectionKeys[id] != nil)) in \(context.channel.clientAddrInfo)")
                if let key = ioData.connectionKeys[id] { 
                    cipher = try Crypto.Symm.encrypt(dataChunk, key: key)
                } else {
                    // 代表首次请求，直接发送明文
                    // 用户凭据可明文发送，且用户口令会加密处理，因此整个请求无需加密
                    cipher = .init(buffer: dataChunk)
                }
                let buffer = ByteBuffer(data: cipher)
                return context.eventLoop.makeSucceededFuture(buffer)
            } catch let err {
                return context.eventLoop.makeFailedFuture(err)
            }
        }

        /// 收到响应时，进行解密并解码
        func get(response: ByteBuffer, bufferStrategy: BufferStrategy, context: ChannelHandlerContext, streaming: Bool) -> EventLoopFuture<(ClientResponse?, ByteBuffer)> {
            guard let ioData = client.apiRequestIoData else { return context.eventLoop.makeFailedFuture(Err.requestParaMissing.d("apiRequestIoData", 12010, (#file, #line))) }
            let id = ObjectIdentifier(context.channel)

            // 检查对方回复的是不是一个未加密的 http 回复，如果是，则表示对方出错

            if let _ = ioData.errorTemps[id] {
                let err = parseError(body: response)
                ioData.errorTemps[id] = nil
                return context.eventLoop.makeFailedFuture(err)
            } else {
                if let status = checkHeader(res: response) {
                    ioData.errorTemps[id] = status
                    return context.eventLoop.makeSucceededFuture((nil, response))
                }
            }

            do {
                logger?.trace("API.Client.HTTP-收到响应，进行解密(key: \(ioData.connectionKeys[id] != nil)) in \(context.channel.clientAddrInfo)")
                var plain: ByteBuffer
                if let key = ioData.connectionKeys[id] {
                    plain = try Crypto.Symm.decrypt(.init(buffer: response), key: key)
                } else {
                    guard let token = Data(base64Encoded: ioData.token) else { throw Err.parseParaFailed.d("用户口令", 14005, (#file, #line)) }
                    let tokenKey = Crypto.Symm.Key(data: token)
                    plain = try Crypto.Symm.decrypt(.init(buffer: response), key: tokenKey)
                }
                let plainStable = plain
                return streamingHandle(
                    chunkData: &plain, 
                    context: context, 
                    bufferStrategy: bufferStrategy,
                    dic: ioData.readingBufferDatas,
                    streaming: streaming
                ).flatMapThrowing { data in
                    if let d = data { return (try ClientResponse(data: d), plainStable) } 
                    else { return (nil, plainStable) }
                }
            } catch let err {
                return context.eventLoop.makeFailedFuture(err)
            }
        }

        // 检查 response 是否为 HTTP 格式的头，如果是，则返回其状态码
        func checkHeader(res: ByteBuffer) -> HTTPStatus? {
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
            struct BodyReply: Content {
                let error: Bool
                let reason: String
            }
            do {
                let reply = try Guard({ try JSONDecoder().decode(BodyReply.self, from: Data(buffer: body)) }, throw: Err.protocolInvalid.d("应当解析出 Error 信息，但失败", 14012, (#file, #line)))
                if reply.error {
                    return Err.internalError.d(reply.reason, 13001, (#file, #line))
                } else {
                    throw Err.protocolInvalid.d("应当解析出 Error 信息，但失败", 14011, (#file, #line))
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
            client.apiRequestIoData?.connectionKeys[id] = nil
            client.apiRequestIoData?.readingBufferDatas[id] = nil
            return context.eventLoop.makeSucceededVoidFuture()
        }
    }
}
