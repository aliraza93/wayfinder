import Foundation

/// Records content-free `RunEvent`s only. No API accepts free-form app content strings.
public final class RunRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var events: [RunEvent] = []

    public init() {}

    public func append(_ event: RunEvent) {
        lock.lock()
        events.append(event)
        lock.unlock()
    }

    public func snapshot() -> [RunEvent] {
        lock.lock()
        defer { lock.unlock() }
        return events
    }

    /// JSONL with fixed field order; optional identity when present.
    public func jsonl(dateFormatter: ISO8601DateFormatter = ISO8601DateFormatter()) -> String {
        snapshot().map { event in
            let ts = dateFormatter.string(from: event.timestamp)
            var line =
                "{\"timestamp\":\"\(ts)\",\"actionKind\":\"\(event.actionKind)\",\"targetBundleID\":\"\(event.targetBundleID)\",\"result\":\"\(event.result.rawValue)\""
            if let identity = event.identity, !identity.isEmpty {
                let escaped = identity
                    .replacingOccurrences(of: "\\", with: "\\\\")
                    .replacingOccurrences(of: "\"", with: "\\\"")
                line += ",\"identity\":\"\(escaped)\""
            }
            line += "}"
            return line
        }.joined(separator: "\n")
    }
}
