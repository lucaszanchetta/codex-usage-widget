import Foundation

public enum UsageStore {
    private static let suiteName = Bundle.main.object(forInfoDictionaryKey: "CodexUsageAppGroup") as? String
    private static let snapshotFileName = "usage-snapshot.json"

    private static var snapshotURL: URL? {
        guard let suiteName, !suiteName.isEmpty else { return nil }
        return FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: suiteName)?.appendingPathComponent(snapshotFileName)
    }

    public static var storageLocation: String {
        snapshotURL?.path ?? "App Group container unavailable (\(suiteName ?? "unconfigured"))"
    }

    public static func save(_ snapshot: UsageSnapshot) throws {
        guard let url = snapshotURL else { throw UsageStoreError.containerUnavailable(suiteName ?? "unconfigured") }
        let data: Data
        do { data = try JSONEncoder.iso8601.encode(snapshot) }
        catch { throw UsageStoreError.encoding(String(describing: error)) }
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        } catch { throw UsageStoreError.directory(url.deletingLastPathComponent().path, String(describing: error)) }
        do { try data.write(to: url, options: [.atomic]) }
        catch { throw UsageStoreError.write(url.path, String(describing: error)) }
    }

    public static func load() -> UsageSnapshot? {
        guard let url = snapshotURL, let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder.iso8601.decode(UsageSnapshot.self, from: data)
    }
}

public enum UsageStoreError: LocalizedError {
    case containerUnavailable(String)
    case encoding(String)
    case directory(String, String)
    case write(String, String)

    public var errorDescription: String? {
        switch self {
        case .containerUnavailable(let suite): return "App Group container unavailable for \(suite). Check the signed App Group entitlement."
        case .encoding(let detail): return "Could not encode the usage snapshot: \(detail)"
        case .directory(let path, let detail): return "Could not create snapshot directory at \(path): \(detail)"
        case .write(let path, let detail): return "Could not atomically write snapshot at \(path): \(detail)"
        }
    }
}

private extension JSONEncoder { static var iso8601: JSONEncoder { let e = JSONEncoder(); e.dateEncodingStrategy = .iso8601; return e } }
private extension JSONDecoder { static var iso8601: JSONDecoder { let d = JSONDecoder(); d.dateDecodingStrategy = .iso8601; return d } }
