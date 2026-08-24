import Foundation

/// Pinned schema version for `workflows.json`.
public enum SchemaVersion {
    /// Current on-disk format written by `ConfigStore`.
    public static let current = 2
    /// Oldest version `Migration` can upgrade.
    public static let minimumSupported = 1
}
