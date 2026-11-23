import XCTest
#if SWIFT_PACKAGE
import CodexUsage
#endif

final class UsageCalculatorTests: XCTestCase {
    func testCalculatesRemainingAndPaceDeltaFromReset() throws {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let reset = now.addingTimeInterval(3.5 * 86_400)
        let resetString = ISO8601DateFormatter().string(from: reset)
        let payload = "{\"product\":\"Codex\",\"weeklyLimits\":[{\"limitId\":\"main\",\"limitName\":\"Weekly\",\"usedPercent\":40,\"remainingPercent\":60,\"resetsAt\":\"\(resetString)\"}]}"
        let snapshot = try UsageCalculator.snapshot(from: Data(payload.utf8), now: now)
        XCTAssertEqual(snapshot.weeklyLimits.first?.remainingPercent, 60)
        XCTAssertEqual(snapshot.weeklyLimits.first?.expectedPercent ?? 0, 50, accuracy: 0.001)
        XCTAssertEqual(snapshot.weeklyLimits.first?.paceDelta ?? 0, -10, accuracy: 0.001)
        XCTAssertEqual(snapshot.weeklyLimits.first?.paceGap(at: now) ?? 0, 10, accuracy: 0.001)
        XCTAssertEqual(UsageCalculator.formatPaceGap(-10), "−10.0 pp ahead")
        XCTAssertEqual(UsageCalculator.formatPaceGap(10), "+10.0 pp behind")
        XCTAssertEqual(snapshot.weeklyLimits.first?.secondsUntilReset, Int(3.5 * 86_400))
    }

    func testRejectsEmptyWeeklyResponse() { XCTAssertThrowsError(try UsageCalculator.snapshot(from: Data(#"{"weeklyLimits":[]}"#.utf8))) }
}
