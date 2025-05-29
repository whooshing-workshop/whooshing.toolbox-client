import NIOCore
import NIOHTTP1
import DataConvertable
import Foundation
import NIOFileSystem
import ErrorHandle
import AsyncAlgorithms

public extension ReqClient {
    enum EncodeErr: String, ErrList {
        public var domain: String { "woo.sys.reqclient.body.encode.err" }
        case fileInfoGetFailed = "文件信息获取失败"
        case fileOperationUnknowErr = "文件操作时出现未知错误"
        case fileReadFailed = "文件读取时失败"
        case fileReadUnknowErr = "文件读取时遇到未知错误"
    }
}

public extension HTTPBody {
    /// 使用 `ByteBuffer` 创建一个 HTTP 请求体。
    ///
    /// - Parameter bytes: 原始字节缓冲区。
    /// - Returns: 构造的 HTTPBody，类型为 `.bytes`，无特殊 Content-Type。
    static func bytes(_ bytes: ByteBuffer) -> Self { .init(type: .bytes(bytes)) }
    
    /// 创建一个以任意可能解包失败的 data 转换类型为内容的 HTTP 请求体。
    ///
    /// - Parameter data: 要编码的原始数据，其转为字节可能出错。
    /// - Returns: 包含二进制内容的 `HTTPBody`，其 `Content-Type` 默认为 `application/octet-stream`；若为字符串则为 `text/plain`。
    /// - Throws: 如果 `data` 转换为字节失败，则抛出相关错误。
    static func data<T: ThrowableDataConvertable>(_ data: T) throws -> Self {
        var headers: HTTPHeaders = ["content-type": "application/octet-stream"]
        if data is String {
            headers.replaceOrAdd(name: "content-type", value: "text/plain")
        }
        return .init(type: try .bytes(.init(data: data.data())), headers: headers)
    }
    
    /// 使用纯文本创建 HTTP 请求体。
    ///
    /// - Parameter text: 文本字符串。
    /// - Returns: 构造的 HTTPBody，Content-Type 为 `text/plain`。
    /// - Throws: 若字符串转换失败将抛出错误。
    static func text(_ text: String) throws -> Self {
        try .data(text)
    }
    
    /// 使用任意支持安全转换的 data 创建 HTTP 请求体。
    ///
    /// - Parameter data: 可转换的数据对象，可安全转换为字节。
    /// - Returns: 构造的 HTTPBody，类型为 `.bytes`。
    static func data<T: SafeDataConvertable>(_ data: T) -> Self {
        .bytes(.init(data: data.data()))
    }
    
    /// 使用 `Encodable` 类型创建 JSON 格式的 HTTP 请求体。
    ///
    /// - Parameter value: 要编码的可编码对象。
    /// - Returns: JSON 编码的 HTTPBody，请求头包含 `application/json`。
    /// - Throws: JSON 编码失败时抛出错误。
    static func json<T: Encodable>(_ value: T) throws -> Self {
        .init(type: .bytes(.init(data: try JSONEncoder().encode(value))), headers: ["content-type": "application/json"])
    }
}

public extension HTTPBody {
    /// 创建一个基于异步数据通道的 HTTP 流式请求体。
    ///
    /// - Parameter stream: 可抛出元素转换为 `ByteBuffer` 的异步通道。
    /// - Returns: 流式 HTTPBody。
    static func stream<T: ThrowableDataConvertable & Sendable>(_ stream: AsyncThrowingChannel<T, Error>) -> Self {
        if let stream = stream as? AsyncThrowingChannel<ByteBuffer, Error> {
            return .init(type: .stream(stream))
        } else {
            let res = AsyncThrowingChannel<ByteBuffer, Error>()
            Task {
                do {
                    for try await chunk in stream {
                        await res.send(.init(data: try chunk.data()))
                    }
                    res.finish()
                } catch {
                    res.fail(error)
                }
            }
            return .init(type: .stream(res))
        }
    }
    
    /// 创建一个基于异步 JSON 编码的 HTTP 流式请求体。
    ///
    /// - Parameter stream: 元素为 `Encodable` 的异步通道。
    /// - Returns: 流式 JSON 请求体，Content-Type 为 `application/json`。
    static func jsonStream<T: Encodable & Sendable>(_ stream: AsyncThrowingChannel<T, Error>) -> Self {
        if let stream = stream as? AsyncThrowingChannel<ByteBuffer, Error> {
            return .init(type: .stream(stream))
        } else {
            let res = AsyncThrowingChannel<ByteBuffer, Error>()
            Task {
                let jsonEncoder = JSONEncoder()
                do {
                    for try await chunk in stream {
                        await res.send(.init(data: try jsonEncoder.encode(chunk)))
                    }
                    res.finish()
                } catch {
                    res.fail(error)
                }
            }
            return .init(type: .stream(res))
        }
    }
    
    /// 使用本地文件创建 HTTP 流式请求体。
    ///
    /// - Parameter:
    ///   - file: 要读取的本地文件路径。
    ///   - progress: 文件发出的进度回调，可从这里读出进度信息。
    ///
    /// - Returns: 分块读取的流式 HTTPBody，Content-Type 为 `application/octet-stream`，并附带文件名作为 `content-disposition`。
    static func file(from file: FilePath, progress: AsyncProgress? = nil) -> Self {
        let res = AsyncThrowingChannel<ByteBuffer, Error>()
        Task {
            var fileHandle: ReadFileHandle? = nil
            do {
                let fh = try await FileSystem.shared.openFile(forReadingAt: file, options: .init())
                fileHandle = fh
                
                let info = try await fh.info()
                progress?.totalBytes = Int(info.size)
                
                for try await chunk in fh.readChunks(chunkLength: .kilobytes(64)) {
                    await res.send(chunk)
                    progress?.sendProgress(chunk.readableBytes)
                }
                try await fh.close()
                res.finish()
                progress?.finish()
            } catch {
                try await fileHandle?.close()
                res.fail(ReqClient.EncodeErr.fileOperationUnknowErr.d(14033).subErr(error))
                progress?.finish(throwing: error)
            }
        }
        
        return .init(type: .stream(res), headers: [
            "content-type": "application/octet-stream",
            "content-disposition": file.lastComponent?.string ?? ""
        ])
    }
}
