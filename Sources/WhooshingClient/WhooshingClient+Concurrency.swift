import NIOCore
import NIOHTTP1

public extension WhooshingClient {
    func get(
        _ url: WebURI,
        body: HTTPBody? = nil,
        headers: HTTPHeaders = [:]
    ) async throws -> HTTPResponse {
        try await send(.GET, to: url, body: body, headers: headers)
    }
    
    func post(
        _ url: WebURI,
        body: HTTPBody? = nil,
        headers: HTTPHeaders = [:]
    ) async throws -> HTTPResponse {
        try await send(.POST, to: url, body: body, headers: headers)
    }
    
    func patch(
        _ url: WebURI,
        body: HTTPBody? = nil,
        headers: HTTPHeaders = [:]
    ) async throws -> HTTPResponse {
        try await send(.PATCH, to: url, body: body, headers: headers)
    }
    
    func put(
        _ url: WebURI,
        body: HTTPBody? = nil,
        headers: HTTPHeaders = [:]
    ) async throws -> HTTPResponse {
        try await send(.PUT, to: url, body: body, headers: headers)
    }
    
    func delete(
        _ url: WebURI,
        body: HTTPBody? = nil,
        headers: HTTPHeaders = [:]
    ) async throws -> HTTPResponse {
        try await send(.DELETE, to: url, body: body, headers: headers)
    }
    
    func send(
        _ method: HTTPMethod,
        to url: WebURI,
        body: HTTPBody? = nil,
        headers: HTTPHeaders = [:]
    ) async throws -> HTTPResponse {
        let request = HTTPRequest(method: method, url: url, headers: headers, body: body)
        return try await  send(request).get()
    }
}
