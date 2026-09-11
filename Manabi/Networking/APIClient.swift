import Foundation

enum APIError: LocalizedError, Sendable {
    case http(Int, String)
    case invalidURL
    case unreadable

    var errorDescription: String? {
        switch self {
        case .invalidURL: "服务地址无效，请填写完整的 http 或 https 地址。"
        case .unreadable: "暂时无法读取学习内容，请重试。"
        case .http(let code, let detail):
            switch code {
            case 401: "登录已过期，请重新登录后继续。"
            case 404: "暂时没有可用的练习内容，请刷新后再试。"
            case 409 where detail.contains("Username"): "这个用户名已经被使用，请换一个。"
            case 409: "这次操作已处理或状态已更新，请返回后重新打开。"
            case 422: "请检查填写内容后重试。"
            case 429: "操作有些频繁，请稍等一分钟再试。"
            default: "学习服务暂时不可用，请稍后重试。"
            }
        }
    }
}

actor APIClient {
    let baseURL: URL
    private var token: String?
    private let session: URLSession

    init(baseURL: URL, token: String? = nil, session: URLSession = .shared) {
        self.baseURL = baseURL
        self.token = token
        self.session = session
    }

    func setToken(_ token: String?) { self.token = token }

    static func validatedURL(_ value: String) throws -> URL {
        guard var parts = URLComponents(string: value.trimmingCharacters(in: .whitespacesAndNewlines)),
              ["http", "https"].contains(parts.scheme?.lowercased() ?? ""),
              let host = parts.host, !host.isEmpty, parts.user == nil, parts.password == nil,
              parts.query == nil, parts.fragment == nil,
              parts.path.isEmpty || parts.path == "/" else { throw APIError.invalidURL }
        parts.path = ""
        guard let url = parts.url else { throw APIError.invalidURL }
        return url
    }

    static func decoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return decoder
    }

    func get<T: Decodable & Sendable>(_ path: String, query: [URLQueryItem] = []) async throws -> T {
        try await request(path, method: "GET", body: nil, query: query)
    }

    func post<T: Decodable & Sendable, B: Encodable & Sendable>(_ path: String, body: B) async throws -> T {
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        return try await request(path, method: "POST", body: encoder.encode(body))
    }

    func patch<T: Decodable & Sendable, B: Encodable & Sendable>(_ path: String, body: B) async throws -> T {
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        return try await request(path, method: "PATCH", body: encoder.encode(body))
    }

    private func request<T: Decodable & Sendable>(_ path: String, method: String, body: Data?, query: [URLQueryItem] = []) async throws -> T {
        guard var parts = URLComponents(url: baseURL.appending(path: "api/v1").appending(path: path), resolvingAgainstBaseURL: false) else { throw APIError.invalidURL }
        if !query.isEmpty { parts.queryItems = query }
        guard let url = parts.url else { throw APIError.invalidURL }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.httpBody = body
        request.timeoutInterval = 20
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let token { request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        let (data, response) = try await session.data(for: request)
        guard let response = response as? HTTPURLResponse else { throw APIError.unreadable }
        guard (200..<300).contains(response.statusCode) else {
            let detail = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["detail"] as? String ?? ""
            throw APIError.http(response.statusCode, detail)
        }
        if response.statusCode == 204, let empty = EmptyBody() as? T { return empty }
        return try Self.decoder().decode(T.self, from: data)
    }
}
