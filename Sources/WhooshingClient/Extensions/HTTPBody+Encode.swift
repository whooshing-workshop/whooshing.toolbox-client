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
    static func bytes(_ bytes: ByteBuffer) -> Self { .init(type: .bytes(bytes)) }
    
    static func data<T: ThrowableDataConvertable>(_ data: T) throws -> Self {
        var headers: HTTPHeaders = ["content-type": "application/octet-stream"]
        if data is String {
            headers.replaceOrAdd(name: "content-type", value: "text/plain")
        }
        return .init(type: try .bytes(.init(data: data.data())), headers: headers)
    }
    
    static func text(_ text: String) throws -> Self {
        try .data(text)
    }
    
    static func data<T: SafeDataConvertable>(_ data: T) -> Self {
        .bytes(.init(data: data.data()))
    }
    
    static func json<T: Encodable>(_ value: T) throws -> Self {
        .init(type: .bytes(.init(data: try JSONEncoder().encode(value))), headers: ["content-type": "application/json"])
    }
}

public extension HTTPBody {
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
    
    static func file(from file: FilePath) -> Self {
        let res = AsyncThrowingChannel<ByteBuffer, Error>()
        Task {
            var fileHandle: ReadFileHandle? = nil
            do {
                let fh = try await FileSystem.shared.openFile(forReadingAt: file, options: .init())
                fileHandle = fh
                for try await chunk in fh.readChunks(chunkLength: .kilobytes(64)) {
                    await res.send(chunk)
                }
                try await fh.close()
                res.finish()
            } catch {
                try await fileHandle?.close()
                res.fail(ReqClient.EncodeErr.fileOperationUnknowErr.d(14033).subErr(error))
            }
        }
        
        return .init(type: .stream(res), headers: [
            "content-type": "application/octet-stream",
            "content-disposition": file.lastComponent?.string ?? ""
        ])
    }
}
