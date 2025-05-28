import NIOCore
import AsyncAlgorithms
import NIOHTTP1
import DataConvertable
import Foundation
import NIOFileSystem
import ErrorHandle

public extension ReqClient {
    enum DecodeErr: String, ErrList {
        public var domain: String { "woo.sys.reqclient.body.decode.err" }
        case bodyTypeNotMatch = "解包失败，类型不符合"
    }
}

public extension HTTPBody {
    func bytes() throws -> ByteBuffer {
        guard case let .bytes(buffer) = self.type else { throw ReqClient.DecodeErr.bodyTypeNotMatch.d(15008) }
        return buffer
    }
    
    func text() throws -> String { try self.data() }
    
    func data<T: ThrowableDataConvertable>(as: T.Type = T.self) throws -> T {
        guard case let .bytes(buffer) = self.type else { throw ReqClient.DecodeErr.bodyTypeNotMatch.d(15009) }
        return try T.init(data: buffer.data())
    }
    
    func data<T: SafeDataConvertable>(as: T.Type = T.self) throws -> T {
        guard case let .bytes(buffer) = self.type else { throw ReqClient.DecodeErr.bodyTypeNotMatch.d(15010) }
        return T.init(data: buffer.data())
    }
    
    func json<T: Decodable>(as: T.Type = T.self) throws -> T {
        guard case let .bytes(buffer) = self.type else { throw ReqClient.DecodeErr.bodyTypeNotMatch.d(150011) }
        return try JSONDecoder().decode(T.self, from: buffer)
    }
}

public extension HTTPBody {
    func stream() throws -> AsyncThrowingChannel<ByteBuffer, Error> {
        try self.stream(as: ByteBuffer.self)
    }
    
    func stream<T: ThrowableDataConvertable & Sendable>(as: T.Type = T.self) throws -> AsyncThrowingChannel<T, Error> {
        guard case let .stream(stream) = self.type else { throw ReqClient.DecodeErr.bodyTypeNotMatch.d(150012) }
        if T.self == ByteBuffer.self {
            return stream as! AsyncThrowingChannel<T, Error>
        } else {
            let res = AsyncThrowingChannel<T, Error>()
            Task {
                do {
                    for try await chunk in stream {
                        await res.send(try .init(data: .init(buffer: chunk)))
                    }
                    res.finish()
                } catch {
                    res.fail(error)
                }
            }
            return res
        }
    }
    
    func jsonStream<T: Decodable & Sendable>(as: T.Type = T.self) throws -> AsyncThrowingChannel<T, Error> {
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
                    }
                    res.finish()
                } catch {
                    res.fail(error)
                }
            }
            return res
        }
    }
    
    func file(to file: FilePath, options: OpenOptions.Write, startAt: Int64 = 0) async throws {
        guard case let .stream(stream) = self.type else { throw ReqClient.DecodeErr.bodyTypeNotMatch.d(150013) }
        var fileHandler: WriteFileHandle? = nil
        do {
            let fh = try await FileSystem.shared.openFile(forWritingAt: file, options: options)
            fileHandler = fh
            var i = startAt
            for try await chunk in stream {
                let res = try await fh.write(contentsOf: chunk, toAbsoluteOffset: i)
                i += res
            }
            try await fh.close()
        } catch {
            try await fileHandler?.close()
            throw error
        }
    }
}

