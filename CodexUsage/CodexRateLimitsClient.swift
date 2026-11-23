import Foundation
import Darwin

public final class CodexRateLimitsClient: @unchecked Sendable {
    public init() {}

    public func fetch() async throws -> UsageSnapshot {
        try await Task.detached(priority: .utility) { try self.fetchSynchronously() }.value
    }

    private func fetchSynchronously() throws -> UsageSnapshot {
        let process = Process(); process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["codex", "app-server", "--listen", "stdio://"]
        var environment = ProcessInfo.processInfo.environment
        environment["PATH"] = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:" + (environment["PATH"] ?? "")
        process.environment = environment
        let input = Pipe(); let output = Pipe(); process.standardInput = input; process.standardOutput = output; process.standardError = FileHandle.nullDevice
        do { try process.run() } catch { throw UsageError.commandFailed("Could not start Codex: \(error.localizedDescription)") }
        defer { if process.isRunning { process.terminate() } }

        send(["id": 1, "method": "initialize", "params": ["clientInfo": ["name": "codex_usage_widget", "version": "1.0", "title": "Codex Usage Widget"], "capabilities": NSNull()]], to: input)
        let reader = JSONLineReader(pipe: output)
        _ = try reader.response(id: 1)
        send(["method": "initialized"], to: input)
        send(["id": 2, "method": "account/rateLimits/read", "params": ["excludeResetCreditDetails": true]], to: input)
        let result = try reader.response(id: 2)
        let items = extractWeeklyItems(from: result)
        let json = try JSONSerialization.data(withJSONObject: ["product": "Codex", "weeklyLimits": items])
        return try UsageCalculator.snapshot(from: json)
    }

    private func send(_ object: [String: Any], to pipe: Pipe) {
        guard var data = try? JSONSerialization.data(withJSONObject: object) else { return }; data.append(10); try? pipe.fileHandleForWriting.write(contentsOf: data)
    }

    private func extractWeeklyItems(from result: [String: Any]) -> [[String: Any]] {
        var snapshots: [(String, [String: Any])] = []
        if let byID = result["rateLimitsByLimitId"] as? [String: [String: Any]] { snapshots = byID.sorted { $0.key < $1.key }.map { ($0.key, $0.value) } }
        else if let limit = result["rateLimits"] as? [String: Any] { snapshots = [("codex", limit)] }
        var items: [[String: Any]] = []
        for (key, snapshot) in snapshots {
            for slot in ["primary", "secondary"] {
                guard let window = snapshot[slot] as? [String: Any], let minutes = window["windowDurationMins"] as? Int, minutes == 7 * 24 * 60,
                      let number = window["usedPercent"] as? NSNumber, number.doubleValue.isFinite else { continue }
                let used = number.doubleValue
                var item: [String: Any] = ["limitId": snapshot["limitId"] as? String ?? key, "limitName": snapshot["limitName"] as? String ?? key, "windowMinutes": minutes, "usedPercent": used, "remainingPercent": max(0, min(100, 100 - used))]
                if let timestamp = (window["resetsAt"] as? NSNumber)?.doubleValue { item["resetsAt"] = ISO8601DateFormatter().string(from: Date(timeIntervalSince1970: timestamp)) }
                items.append(item)
            }
        }
        return items
    }
}

private final class JSONLineReader {
    private let pipe: Pipe
    private var buffer = Data()

    init(pipe: Pipe) { self.pipe = pipe }

    func response(id: Int) throws -> [String: Any] {
        let deadline = DispatchTime.now() + .seconds(30)
        while true {
            while let newline = buffer.firstIndex(of: 10) {
                let line = buffer.prefix(upTo: newline)
                buffer.removeSubrange(...newline)
                guard let object = try? JSONSerialization.jsonObject(with: Data(line)) as? [String: Any], object["id"] as? Int == id else { continue }
                if let error = object["error"] as? [String: Any] { throw UsageError.commandFailed(error["message"] as? String ?? "Codex returned an error") }
                guard let result = object["result"] as? [String: Any] else { throw UsageError.invalidResponse }
                return result
            }

            let now = DispatchTime.now()
            guard now < deadline else { break }
            let remainingNanos = deadline.uptimeNanoseconds - now.uptimeNanoseconds
            let milliseconds = Int32((remainingNanos + 999_999) / 1_000_000)
            var descriptor = pollfd(fd: pipe.fileHandleForReading.fileDescriptor, events: Int16(POLLIN), revents: 0)
            let status = poll(&descriptor, 1, milliseconds)
            if status < 0 {
                if errno == EINTR { continue }
                throw UsageError.commandFailed("Could not read Codex response")
            }
            if status == 0 { continue }
            let data = pipe.fileHandleForReading.availableData
            if data.isEmpty { throw UsageError.commandFailed("Codex app-server exited before responding. Check `codex login status`.") }
            buffer.append(data)
        }
        throw UsageError.commandFailed("Timed out waiting for Codex app-server")
    }
}
