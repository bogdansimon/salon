import Foundation

/// The single network seam. Sources talk to this, tests swap in fixtures.
public protocol HTTPClient: Sendable {
    func data(for request: URLRequest) async throws -> Data
}

public enum SalonHTTP {
    /// Wikimedia and the Art Institute ask clients to identify themselves.
    public static let userAgent = "Salon/1.0 (+https://github.com/bogdansimon/salon)"
    public static let timeout: TimeInterval = 20
}

public struct URLSessionHTTPClient: HTTPClient {
    private let session: URLSession

    public init(session: URLSession = .shared) {
        self.session = session
    }

    public func data(for request: URLRequest) async throws -> Data {
        var request = request
        request.timeoutInterval = SalonHTTP.timeout
        if request.value(forHTTPHeaderField: "User-Agent") == nil {
            request.setValue(SalonHTTP.userAgent, forHTTPHeaderField: "User-Agent")
        }
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw SourceError.badResponse }
        guard (200..<300).contains(http.statusCode) else { throw SourceError.http(status: http.statusCode) }
        return data
    }
}

extension HTTPClient {
    func json<T: Decodable>(_ type: T.Type, from request: URLRequest) async throws -> T {
        let data = try await data(for: request)
        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            throw SourceError.decoding(String(describing: error))
        }
    }

    func json<T: Decodable>(_ type: T.Type, from url: URL, headers: [String: String] = [:]) async throws -> T {
        var request = URLRequest(url: url)
        headers.forEach { request.setValue($1, forHTTPHeaderField: $0) }
        return try await json(type, from: request)
    }
}

extension URL {
    /// Builds a URL from a base and query items; crashes only on programmer error (bad literal).
    static func make(_ base: String, _ query: [String: String] = [:]) -> URL {
        var components = URLComponents(string: base)!
        if !query.isEmpty {
            components.queryItems = query.sorted { $0.key < $1.key }.map { URLQueryItem(name: $0.key, value: $0.value) }
        }
        return components.url!
    }
}
