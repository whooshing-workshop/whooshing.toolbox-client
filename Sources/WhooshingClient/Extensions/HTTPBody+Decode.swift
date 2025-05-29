import NIOCore
import AsyncAlgorithms
import NIOHTTP1
import DataConvertable
import Foundation
import NIOFileSystem
import ErrorHandle

/// 表示 HTTP 请求体解码失败的错误类型。
/// 包含类型不匹配等常见错误码。
public extension ReqClient {
    enum DecodeErr: String, ErrList {
        public var domain: String { "woo.sys.reqclient.body.decode.err" }
        case bodyTypeNotMatch = "解包失败，类型不符合"
    }
}

public extension HTTPBody {
    /// 将请求体转换为 ByteBuffer。
    ///
    /// - Returns: 请求体中的 ByteBuffer。
    /// - Throws: 若类型不为 `.bytes`，抛出 `DecodeErr.bodyTypeNotMatch`。
    func bytes() throws -> ByteBuffer {
        guard case let .bytes(buffer) = self.type else { throw ReqClient.DecodeErr.bodyTypeNotMatch.d(15008) }
        return buffer
    }
    
    /// 将请求体转换为字符串（默认使用 UTF-8）。
    ///
    /// - Returns: 解码后的字符串内容。
    /// - Throws: 若类型不为 `.bytes`，或字符串解码失败，抛出错误。
    func text() throws -> String { try self.data() }
    
    /// 将请求体内容解码为任意符合 `ThrowableDataConvertable` 的类型。
    ///
    /// - Parameter as: 要解码的目标类型。
    /// - Returns: 解码后的对象。
    /// - Throws: 若类型不匹配或转换失败。
    func data<T: ThrowableDataConvertable>(as: T.Type = T.self) throws -> T {
        guard case let .bytes(buffer) = self.type else { throw ReqClient.DecodeErr.bodyTypeNotMatch.d(15009) }
        return try T.init(data: buffer.data())
    }
    
    /// 将请求体内容转换为任意符合 `SafeDataConvertable` 的类型。
    ///
    /// - Parameter as: 要转换的目标类型。
    /// - Returns: 转换后的对象。
    /// - Throws: 若类型不匹配或转换失败。
    func data<T: SafeDataConvertable>(as: T.Type = T.self) throws -> T {
        guard case let .bytes(buffer) = self.type else { throw ReqClient.DecodeErr.bodyTypeNotMatch.d(15010) }
        return T.init(data: buffer.data())
    }
    
    /// 将请求体解码为指定的 JSON 类型。
    ///
    /// - Parameter as: 要解码的 `Decodable` 类型。
    /// - Returns: 解码后的对象。
    /// - Throws: 若类型不为 `.bytes` 或 JSON 解码失败。
    func json<T: Decodable>(as: T.Type = T.self) throws -> T {
        guard case let .bytes(buffer) = self.type else { throw ReqClient.DecodeErr.bodyTypeNotMatch.d(150011) }
        return try JSONDecoder().decode(T.self, from: buffer)
    }
}

public extension HTTPBody {
    /// 返回请求体作为 ByteBuffer 流的异步通道。
    ///
    /// - Returns: ByteBuffer 异步通道。
    /// - Throws: 若类型不为 `.stream`，抛出错误。
    func stream() throws -> AsyncThrowingChannel<ByteBuffer, Error> {
        try self.stream(as: ByteBuffer.self)
    }
    
    /// 将请求体作为异步流解析为指定类型元素的通道。
    ///
    /// - Parameter
    ///   - as: 要转换的元素类型，需符合 `ThrowableDataConvertable`。
    /// - Returns: 异步数据通道。
    /// - Throws: 若类型不为 `.stream` 或转换失败。
    func stream<T: ThrowableDataConvertable & Sendable>(as: T.Type = T.self, progress: AsyncProgress? = nil) throws -> AsyncThrowingChannel<T, Error> {
        guard case let .stream(stream) = self.type else { throw ReqClient.DecodeErr.bodyTypeNotMatch.d(150012) }
        if T.self == ByteBuffer.self {
            return stream as! AsyncThrowingChannel<T, Error>
        } else {
            let res = AsyncThrowingChannel<T, Error>()
            Task {
                do {
                    for try await chunk in stream {
                        await res.send(try .init(data: .init(buffer: chunk)))
                        progress?.sendProgress(chunk.readableBytes)
                    }
                    res.finish()
                    progress?.finish()
                } catch {
                    res.fail(error)
                    progress?.finish(throwing: error)
                }
            }
            return res
        }
    }
    
    /// 将请求体中的流式 JSON 解码为异步通道。
    ///
    /// - Parameter
    ///   - as: 要解码的目标类型。
    ///   - progress: 文件写入的进度回调，可从这里读出进度信息。
    /// - Returns: 解码后的异步通道。
    /// - Throws: 若类型不为 `.stream` 或 JSON 解码失败。
    func jsonStream<T: Decodable & Sendable>(as: T.Type = T.self, progress: AsyncProgress? = nil) throws -> AsyncThrowingChannel<T, Error> {
        guard case let .stream(stream) = self.type else { throw ReqClient.DecodeErr.bodyTypeNotMatch.d(150012) }
        if T.self == ByteBuffer.self {
            return stream as! AsyncThrowingChannel<T, Error>
        } else {
            let res = AsyncThrowingChannel<T, Error>()
            Task {
                let decoder = JSONDecoder()
                do {
                    for try await chunk in stream {
                        let data = try decoder.decode(T.self, from: chunk)
                        await res.send(data)
                        progress?.sendProgress(chunk.readableBytes)
                    }
                    res.finish()
                    progress?.finish()
                } catch {
                    res.fail(error)
                    progress?.finish(throwing: error)
                }
            }
            return res
        }
    }
    
    /// 将请求体中的流式数据保存为文件。
    ///
    /// - Parameters:
    ///   - file: 要写入的目标文件路径。
    ///   - options: 写入选项。
    ///   - startAt: 起始偏移量，默认从 0 开始。
    ///   - progress: 文件写入的进度回调，可从这里读出进度信息。
    /// - Throws: 若类型不为 `.stream`，文件打开、写入或关闭失败则抛出错误。
    func file(to file: FilePath, options: OpenOptions.Write, startAt: Int64 = 0, progress: AsyncProgress? = nil) async throws {
        guard case let .stream(stream) = self.type else { throw ReqClient.DecodeErr.bodyTypeNotMatch.d(150013) }
        var fileHandler: WriteFileHandle? = nil
        do {
            let fh = try await FileSystem.shared.openFile(forWritingAt: file, options: options)
            fileHandler = fh
            var i = startAt
            for try await chunk in stream {
                let res = try await fh.write(contentsOf: chunk, toAbsoluteOffset: i)
                progress?.sendProgress(chunk.readableBytes)
                i += res
            }
            try await fh.close()
            progress?.finish()
        } catch {
            try await fileHandler?.close()
            progress?.finish(throwing: error)
            throw error
        }
    }
}
