import NIOCore
import AsyncAlgorithms
import NIOHTTP1
import DataConvertable
import Foundation
import NIOFileSystem
import ErrorHandle

/// 表示 HTTP 请求体解码失败的错误类型。
/// 包含类型不匹配等常见错误码。
public extension HTTPBody {
    enum DecodeErrcase: String, ErrList {
        case dataDecodeFailed = "数据解码失败"
        case bodyTypeNotMatch = "数据解码失败，类型不符合"
        case streamDecodeFailed = "流数据解码失败"
        
        case fileWriteUnknowErr = "文件写入时遇到未知错误"
    }
}

public extension HTTPBody {
    /// 将请求体转换为 ByteBuffer。
    ///
    /// - Returns: 请求体中的 ByteBuffer。
    /// - Throws: 若类型不为 `.bytes`，抛出 `DecodeErr.bodyTypeNotMatch`。
    func bytes() -> Res<ByteBuffer, DecodeErrcase> {
        guard case let .bytes(buffer) = self.type else {
            return .failure(.bodyTypeNotMatch)
        }
        return .success(buffer)
    }
    
    /// 将请求体转换为字符串（默认使用 UTF-8）。
    ///
    /// - Returns: 解码后的字符串内容。
    /// - Throws: 若类型不为 `.bytes`，或字符串解码失败，抛出错误。
    func text() -> Res<String, DecodeErrcase> { self.data() }
    
    /// 将请求体内容解码为任意符合 `ThrowableDataConvertable` 的类型。
    ///
    /// - Parameter as: 要解码的目标类型。
    /// - Returns: 解码后的对象。
    /// - Throws: 若类型不匹配或转换失败。
    func data<T: ThrowableDataConvertable>(as: T.Type = T.self) -> Res<T, DecodeErrcase> {
        guard case let .bytes(buffer) = self.type else {
            return .failure(.bodyTypeNotMatch)
        }
        return T.make(data: buffer.data).mapError(as: DecodeErrcase.dataDecodeFailed)
    }
    
    /// 将请求体内容转换为任意符合 `SafeDataConvertable` 的类型。
    ///
    /// - Parameter as: 要转换的目标类型。
    /// - Returns: 转换后的对象。
    /// - Throws: 若类型不匹配或转换失败。
    func data<T: SafeDataConvertable>(as: T.Type = T.self) -> Res<T, DecodeErrcase> {
        guard case let .bytes(buffer) = self.type else {
            return .failure(.bodyTypeNotMatch)
        }
        
        return .success(T.new(data: buffer.data))
    }
    
    /// 将请求体解码为指定的 JSON 类型。
    ///
    /// - Parameter as: 要解码的 `Decodable` 类型。
    /// - Returns: 解码后的对象。
    /// - Throws: 若类型不为 `.bytes` 或 JSON 解码失败。
    func json<T: Decodable>(as: T.Type = T.self) -> Res<T, DecodeErrcase> {
        guard case let .bytes(buffer) = self.type else {
            return .failure(.bodyTypeNotMatch)
        }
        
        return .init(throws: DecodeErrcase.dataDecodeFailed) {
            try JSONDecoder().decode(T.self, from: buffer)
        }
    }
}

public extension HTTPBody {
    /// 返回请求体作为 ByteBuffer 流的异步通道。
    ///
    /// - Returns: ByteBuffer 异步通道。
    /// - Throws: 若类型不为 `.stream`，抛出错误。
    func stream() -> Res<AsyncThrowingChannel<ByteBuffer, Error>, DecodeErrcase> {
        self.stream(as: ByteBuffer.self)
    }
    
    /// 将请求体作为异步流解析为指定类型元素的通道。
    ///
    /// - Parameter
    ///   - as: 要转换的元素类型，需符合 `ThrowableDataConvertable`。
    /// - Returns: 异步数据通道。
    /// - Throws: 若类型不为 `.stream` 或转换失败。
    func stream<T: ThrowableDataConvertable & Sendable>(as: T.Type = T.self, progress: AsyncProgress? = nil) -> Res<AsyncThrowingChannel<T, Error>, DecodeErrcase> {
        guard case let .stream(stream) = self.type else {
            return .failure(.bodyTypeNotMatch)
        }
        
        if let stream = stream as? AsyncThrowingChannel<T, Error> {
            return .success(stream)
        } else {
            let res = AsyncThrowingChannel<T, Error>()
            Task {
                do {
                    for try await chunk in stream {
                        await res.send(try T.make(data: .init(buffer: chunk)).get())
                        progress?.sendProgress(chunk.readableBytes)
                    }
                    res.finish()
                    progress?.finish()
                } catch {
                    let err = DecodeErrcase.streamDecodeFailed.subErr(error)
                    res.fail(err)
                    progress?.finish(throwing: error)
                }
            }
            return .success(res)
        }
    }
    
    /// 将请求体中的流式 JSON 解码为异步通道。
    ///
    /// - Parameter
    ///   - as: 要解码的目标类型。
    ///   - progress: 文件写入的进度回调，可从这里读出进度信息。
    /// - Returns: 解码后的异步通道。
    /// - Throws: 若类型不为 `.stream` 或 JSON 解码失败。
    func jsonStream<T: Decodable & Sendable>(as: T.Type = T.self, progress: AsyncProgress? = nil) -> Res<AsyncThrowingChannel<T, Error>, DecodeErrcase> {
        guard case let .stream(stream) = self.type else {
            return .failure(.bodyTypeNotMatch)
        }
        
        if let stream = stream as? AsyncThrowingChannel<T, Error> {
            return .success(stream)
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
                    let err = DecodeErrcase.streamDecodeFailed.subErr(error)
                    res.fail(err)
                    progress?.finish(throwing: error)
                }
            }
            return .success(res)
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
    func file(to file: FilePath, options: OpenOptions.Write, startAt: Int64 = 0, progress: AsyncProgress? = nil) async -> Res<Void, DecodeErrcase> {
        guard case let .stream(stream) = self.type else {
            return .failure(.bodyTypeNotMatch)
        }
        
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
            try? await fileHandler?.close()
            progress?.finish(throwing: error)
            return .failure(.fileWriteUnknowErr, subErr: error)
        }
        
        return .success(())
    }
}
