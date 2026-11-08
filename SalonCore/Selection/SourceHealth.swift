import Foundation

/// Rolling health record for one source, persisted in health.json.
public struct SourceHealth: Codable, Hashable, Sendable {
    public enum Status: String, Sendable { case unknown, healthy, degraded, failing }

    /// A source is skipped after this many failures in a row (matches the Sources design).
    public static let failingAfter = 3
    /// Answers slower than this mark the source degraded.
    public static let slowLatency: TimeInterval = 8

    public var lastSuccess: Date?
    public var lastAttempt: Date?
    public var lastLatency: TimeInterval?
    public var lastError: String?
    public var consecutiveFailures = 0

    public init() {}

    public var status: Status {
        if consecutiveFailures >= Self.failingAfter { return .failing }
        if consecutiveFailures > 0 { return .degraded }
        if let latency = lastLatency, latency > Self.slowLatency { return .degraded }
        return lastSuccess == nil ? .unknown : .healthy
    }

    public mutating func recordSuccess(latency: TimeInterval, at date: Date = Date()) {
        lastSuccess = date
        lastAttempt = date
        lastLatency = latency
        lastError = nil
        consecutiveFailures = 0
    }

    public mutating func recordFailure(_ error: Error, latency: TimeInterval? = nil, at date: Date = Date()) {
        lastAttempt = date
        lastLatency = latency ?? lastLatency
        lastError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        consecutiveFailures += 1
    }
}

/// What the picker reports back while it works, so the app can update health.
public enum HealthEvent: Sendable {
    case success(latency: TimeInterval)
    case failure(error: Error, latency: TimeInterval)
}
