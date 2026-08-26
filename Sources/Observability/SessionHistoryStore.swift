import Foundation

/// Local persistence for session history (Application Support — no network).
public struct SessionHistoryStore: Sendable {
    public let baseDirectory: URL
    public var maxSessions: Int

    public var historyFileURL: URL {
        baseDirectory.appendingPathComponent("session-history.json", isDirectory: false)
    }

    public init(baseDirectory: URL? = nil, maxSessions: Int = 100) {
        if let baseDirectory {
            self.baseDirectory = baseDirectory
        } else {
            let support = FileManager.default.urls(
                for: .applicationSupportDirectory,
                in: .userDomainMask
            ).first!
            // Folder name kept for config compatibility with workflows.json.
            self.baseDirectory = support.appendingPathComponent("Waypoint", isDirectory: true)
        }
        self.maxSessions = max(10, maxSessions)
    }

    public func load() throws -> SessionHistoryDocument {
        guard FileManager.default.fileExists(atPath: historyFileURL.path) else {
            return SessionHistoryDocument()
        }
        let data: Data
        do {
            data = try Data(contentsOf: historyFileURL)
        } catch {
            throw SessionHistoryStoreError.io("failed to read \(historyFileURL.path): \(error.localizedDescription)")
        }
        do {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            return try decoder.decode(SessionHistoryDocument.self, from: data)
        } catch {
            throw SessionHistoryStoreError.decoding(error.localizedDescription)
        }
    }

    public func save(_ document: SessionHistoryDocument) throws {
        var toSave = document
        toSave.schemaVersion = 1
        if toSave.sessions.count > maxSessions {
            toSave.sessions = Array(
                toSave.sessions.sorted { $0.startedAt > $1.startedAt }.prefix(maxSessions)
            )
        }

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data: Data
        do {
            data = try encoder.encode(toSave)
        } catch {
            throw SessionHistoryStoreError.decoding("encode failed: \(error.localizedDescription)")
        }

        do {
            try FileManager.default.createDirectory(
                at: baseDirectory,
                withIntermediateDirectories: true
            )
            try data.write(to: historyFileURL, options: .atomic)
        } catch let error as SessionHistoryStoreError {
            throw error
        } catch {
            throw SessionHistoryStoreError.io("failed to write \(historyFileURL.path): \(error.localizedDescription)")
        }
    }

    public func append(_ record: SessionHistoryRecord) throws {
        var document = (try? load()) ?? SessionHistoryDocument()
        document.sessions.insert(record, at: 0)
        try save(document)
    }

    public func clear() throws {
        try save(SessionHistoryDocument(sessions: []))
    }
}

public enum SessionHistoryStoreError: Error, Equatable, Sendable {
    case io(String)
    case decoding(String)
}
