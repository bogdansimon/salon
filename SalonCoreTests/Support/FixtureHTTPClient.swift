import Foundation
@testable import SalonCore

/// Serves recorded fixtures instead of the network. Routes match on a substring of
/// the full URL (first match wins). Unmatched requests fail the call, so tests
/// never touch the network.
final class FixtureHTTPClient: HTTPClient, @unchecked Sendable {
    struct Route {
        var match: String
        var response: Result<Data, Error>
    }

    private var routes: [Route] = []
    private let lock = NSLock()
    private(set) var requests: [URLRequest] = []

    func on(_ match: String, fixture name: String) {
        routes.append(Route(match: match, response: .success(Fixtures.data(name))))
    }

    func on(_ match: String, data: Data) {
        routes.append(Route(match: match, response: .success(data)))
    }

    func on(_ match: String, error: Error) {
        routes.append(Route(match: match, response: .failure(error)))
    }

    func data(for request: URLRequest) async throws -> Data {
        lock.lock()
        requests.append(request)
        let url = request.url?.absoluteString.removingPercentEncoding ?? ""
        let route = routes.first { url.contains($0.match) }
        lock.unlock()
        guard let route else { throw SourceError.http(status: 599) }
        return try route.response.get()
    }

    func requestURLs() -> [String] {
        lock.lock(); defer { lock.unlock() }
        return requests.compactMap { $0.url?.absoluteString.removingPercentEncoding }
    }
}

enum Fixtures {
    static var directory: URL {
        Bundle(for: FixtureHTTPClient.self).resourceURL!.appendingPathComponent("Fixtures")
    }

    static func data(_ name: String) -> Data {
        let url = directory.appendingPathComponent(name)
        guard let data = try? Data(contentsOf: url) else { fatalError("Missing fixture \(name)") }
        return data
    }
}

/// In-memory catalog store for sources that cache lists.
final class MemoryCatalogStore: CatalogStore, @unchecked Sendable {
    var files: [String: Data] = [:]
    func load(_ name: String) -> Data? { files[name] }
    func save(_ data: Data, as name: String) { files[name] = data }
}
