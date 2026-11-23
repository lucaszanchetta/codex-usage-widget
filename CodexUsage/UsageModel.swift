import Foundation

public struct WeeklyLimit: Codable, Equatable, Identifiable, Sendable {
    public let id: String
    public let limitName: String
    public let usedPercent: Double
    public let remainingPercent: Double
    public let resetsAt: Date?
    public let secondsUntilReset: Int?
    public let expectedPercent: Double?
    public let paceDelta: Double?

    public init(id: String, limitName: String, usedPercent: Double, remainingPercent: Double, resetsAt: Date? = nil, secondsUntilReset: Int? = nil, expectedPercent: Double? = nil, paceDelta: Double? = nil) {
        self.id = id; self.limitName = limitName; self.usedPercent = usedPercent; self.remainingPercent = remainingPercent
        self.resetsAt = resetsAt; self.secondsUntilReset = secondsUntilReset; self.expectedPercent = expectedPercent; self.paceDelta = paceDelta
    }

    public func secondsUntilReset(at now: Date) -> Int? {
        guard let resetsAt else { return nil }
        return max(0, Int(resetsAt.timeIntervalSince(now).rounded()))
    }

    public func expectedPercent(at now: Date) -> Double? {
        guard let resetsAt else { return nil }
        let elapsed = now.timeIntervalSince(resetsAt.addingTimeInterval(-UsageCalculator.weeklyWindowSeconds))
        guard elapsed >= 0, elapsed <= UsageCalculator.weeklyWindowSeconds else { return nil }
        return min(100, max(0, elapsed / UsageCalculator.weeklyWindowSeconds * 100))
    }

    public func paceDelta(at now: Date) -> Double? {
        expectedPercent(at: now).map { usedPercent - $0 }
    }

    /// Negative means usage is ahead of the even-pace target; positive means behind.
    public func paceGap(at now: Date) -> Double? {
        expectedPercent(at: now).map { $0 - usedPercent }
    }
}

public struct UsageSnapshot: Codable, Equatable, Sendable {
    public let product: String
    public let weeklyLimits: [WeeklyLimit]
    public let fetchedAt: Date
    public let errorMessage: String?

    public init(product: String = "Codex", weeklyLimits: [WeeklyLimit], fetchedAt: Date = Date(), errorMessage: String? = nil) {
        self.product = product; self.weeklyLimits = weeklyLimits; self.fetchedAt = fetchedAt; self.errorMessage = errorMessage
    }
}

public enum UsageCalculator {
    public static let weeklyWindowSeconds: TimeInterval = 7 * 24 * 60 * 60

    public static func snapshot(from data: Data, now: Date = Date()) throws -> UsageSnapshot {
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
        let response = try decoder.decode(RateLimitResponse.self, from: data)
        let limits = response.weeklyLimits.enumerated().map { index, source in
            let used = min(100, max(0, source.usedPercent))
            let remaining = min(100, max(0, source.remainingPercent ?? (100 - used)))
            let expected = source.resetsAt.map { reset in
                min(100, max(0, now.timeIntervalSince(reset.addingTimeInterval(-weeklyWindowSeconds)) / weeklyWindowSeconds * 100))
            }
            let identifier = source.limitId ?? "weekly-\(index)"
            return WeeklyLimit(id: identifier, limitName: source.limitName ?? identifier, usedPercent: used, remainingPercent: remaining,
                               resetsAt: source.resetsAt, secondsUntilReset: source.resetsAt.map { max(0, Int($0.timeIntervalSince(now).rounded())) },
                               expectedPercent: expected, paceDelta: expected.map { used - $0 })
        }
        guard !limits.isEmpty else { throw UsageError.noWeeklyWindow }
        return UsageSnapshot(product: response.product ?? "Codex", weeklyLimits: limits, fetchedAt: now)
    }

    public static func formatDuration(_ seconds: Int?) -> String {
        guard let seconds else { return "Reset time unavailable" }
        let days = seconds / 86_400; let hours = (seconds % 86_400) / 3_600; let minutes = (seconds % 3_600) / 60
        if days > 0 { return "in \(days)d \(hours)h" }; if hours > 0 { return "in \(hours)h \(minutes)m" }; return "in \(minutes)m"
    }

    public static func formatPaceGap(_ gap: Double?) -> String {
        guard let gap else { return "Pace gap unavailable" }
        if abs(gap) < 0.05 { return "On pace" }
        let sign = gap < 0 ? "−" : "+"
        let label = gap < 0 ? "ahead" : "behind"
        return "\(sign)\(String(format: "%.1f", abs(gap))) pp \(label)"
    }

    public static let staleAfter: TimeInterval = 30 * 60

    public static func isStale(_ snapshot: UsageSnapshot, at now: Date = Date(), threshold: TimeInterval = staleAfter) -> Bool {
        now.timeIntervalSince(snapshot.fetchedAt) > threshold
    }
}

public enum UsageError: LocalizedError {
    case noWeeklyWindow
    case commandFailed(String)
    case invalidResponse
    public var errorDescription: String? {
        switch self { case .noWeeklyWindow: return "No seven-day Codex usage window was returned."; case .commandFailed(let message): return message; case .invalidResponse: return "Codex returned an invalid usage response." }
    }
}

private struct RateLimitResponse: Decodable { let product: String?; let weeklyLimits: [RateLimitItem] }
private struct RateLimitItem: Decodable { let limitId: String?; let limitName: String?; let usedPercent: Double; let remainingPercent: Double?; let resetsAt: Date? }
