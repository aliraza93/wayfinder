import Foundation

/// Upgrades on-disk JSON from older schema versions to `SchemaVersion.current`.
public enum Migration {
    /// Migrates a parsed JSON root object in place through successive version steps.
    public static func migrateToCurrent(_ root: inout [String: Any]) throws {
        let rawVersion = root["schemaVersion"]
        let version: Int
        if rawVersion == nil {
            version = 1
        } else if let intVersion = rawVersion as? Int {
            version = intVersion
        } else if let number = rawVersion as? NSNumber {
            version = number.intValue
        } else {
            throw ConfigError.invalidValue(path: "schemaVersion", detail: "expected Int")
        }

        guard version >= SchemaVersion.minimumSupported else {
            throw ConfigError.unsupportedSchemaVersion(version)
        }
        guard version <= SchemaVersion.current else {
            throw ConfigError.unsupportedSchemaVersion(version)
        }

        var current = version
        while current < SchemaVersion.current {
            switch current {
            case 1:
                try migrateV1toV2(&root)
                current = 2
            default:
                throw ConfigError.migrationFailed("no migration from v\(current)")
            }
        }
        root["schemaVersion"] = SchemaVersion.current
    }

    /// v1 used `class` on targets; v2 uses `classification`.
    private static func migrateV1toV2(_ root: inout [String: Any]) throws {
        guard let workflows = root["workflows"] as? [[String: Any]] else {
            throw ConfigError.migrationFailed("v1 document missing workflows array")
        }

        var migratedWorkflows: [[String: Any]] = []
        for (index, workflow) in workflows.enumerated() {
            var copy = workflow
            guard var targets = copy["targets"] as? [[String: Any]] else {
                throw ConfigError.migrationFailed("workflow[\(index)] missing targets")
            }
            for tIndex in targets.indices {
                if let legacy = targets[tIndex]["class"] as? String {
                    if targets[tIndex]["classification"] != nil {
                        throw ConfigError.migrationFailed(
                            "workflow[\(index)].targets[\(tIndex)] has both class and classification"
                        )
                    }
                    targets[tIndex].removeValue(forKey: "class")
                    targets[tIndex]["classification"] = legacy
                }
            }
            copy["targets"] = targets
            migratedWorkflows.append(copy)
        }
        root["workflows"] = migratedWorkflows
    }
}
