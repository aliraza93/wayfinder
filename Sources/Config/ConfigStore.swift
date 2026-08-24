import Domain
import Foundation

/// Loads and saves `workflows.json` under an injectable base directory.
///
/// Default location: `~/Library/Application Support/Waypoint/workflows.json`.
public struct ConfigStore: Sendable {
    public let baseDirectory: URL
    public let validator: WorkflowValidator

    public var workflowsFileURL: URL {
        baseDirectory.appendingPathComponent("workflows.json", isDirectory: false)
    }

    /// - Parameters:
    ///   - baseDirectory: Directory that contains `workflows.json`. When `nil`, uses
    ///     `Application Support/Waypoint`.
    ///   - validator: Validator applied after load and before save.
    public init(
        baseDirectory: URL? = nil,
        validator: WorkflowValidator = WorkflowValidator()
    ) {
        if let baseDirectory {
            self.baseDirectory = baseDirectory
        } else {
            let support = FileManager.default.urls(
                for: .applicationSupportDirectory,
                in: .userDomainMask
            ).first!
            self.baseDirectory = support.appendingPathComponent("Waypoint", isDirectory: true)
        }
        self.validator = validator
    }

    public func load() throws -> WorkflowConfigDocument {
        let data: Data
        do {
            data = try Data(contentsOf: workflowsFileURL)
        } catch {
            throw ConfigError.io("failed to read \(workflowsFileURL.path): \(error.localizedDescription)")
        }
        return try decodeDocument(from: data)
    }

    public func save(_ document: WorkflowConfigDocument) throws {
        try validator.validate(document: document)

        var toSave = document
        toSave.schemaVersion = SchemaVersion.current

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data: Data
        do {
            data = try encoder.encode(toSave)
        } catch {
            throw ConfigError.decoding("encode failed: \(error.localizedDescription)")
        }

        do {
            try FileManager.default.createDirectory(
                at: baseDirectory,
                withIntermediateDirectories: true
            )
            try data.write(to: workflowsFileURL, options: .atomic)
        } catch let error as ConfigError {
            throw error
        } catch {
            throw ConfigError.io("failed to write \(workflowsFileURL.path): \(error.localizedDescription)")
        }
    }

    /// Decode path used by `load` and by tests (migration + strict keys).
    public func decodeDocument(from data: Data) throws -> WorkflowConfigDocument {
        let object: Any
        do {
            object = try JSONSerialization.jsonObject(with: data, options: [])
        } catch {
            throw ConfigError.decoding("invalid JSON: \(error.localizedDescription)")
        }

        guard var root = object as? [String: Any] else {
            throw ConfigError.decoding("root must be a JSON object")
        }

        try Migration.migrateToCurrent(&root)

        let migratedData: Data
        do {
            migratedData = try JSONSerialization.data(withJSONObject: root, options: [])
        } catch {
            throw ConfigError.migrationFailed("re-serialize after migration failed")
        }

        let decoder = JSONDecoder()
        let document: WorkflowConfigDocument
        do {
            document = try decoder.decode(WorkflowConfigDocument.self, from: migratedData)
        } catch {
            throw Self.mapDecodeError(error)
        }

        try validator.validate(document: document)
        return document
    }

    private static func mapDecodeError(_ error: Error) -> ConfigError {
        if let configError = error as? ConfigError {
            return configError
        }
        if let decoding = error as? DecodingError {
            switch decoding {
            case .dataCorrupted(let context):
                if let underlying = context.underlyingError {
                    return mapDecodeError(underlying)
                }
            case .keyNotFound(let key, let context):
                return .missingKey(
                    path: context.codingPath.map(\.stringValue).joined(separator: ".") ,
                    key: key.stringValue
                )
            case .typeMismatch(_, let context), .valueNotFound(_, let context):
                return .decoding(context.debugDescription)
            @unknown default:
                break
            }
        }
        return .decoding(String(describing: error))
    }
}
