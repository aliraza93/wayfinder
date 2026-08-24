import AppKit
import Foundation

public enum ExistingFileOpenerError: Error, Equatable, Sendable {
    case emptyPath
    case fileNotFound(String)
    case appNotFound(String)
    case openFailed
}

/// Opens an **existing** file with a specific already-installed app via AppKit — never by typing a path.
public struct ExistingFileOpener: Sendable {
    public init() {}

    /// Expands `~` and verifies the path refers to an existing file (not a directory).
    public static func resolvedExistingFileURL(path: String) throws -> URL {
        let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw ExistingFileOpenerError.emptyPath }
        let expanded = (trimmed as NSString).expandingTildeInPath
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: expanded, isDirectory: &isDir), !isDir.boolValue else {
            throw ExistingFileOpenerError.fileNotFound(expanded)
        }
        return URL(fileURLWithPath: expanded)
    }

    /// Opens `path` with the application identified by `bundleID`.
    public func open(path: String, withBundleID bundleID: String) async throws {
        let fileURL = try Self.resolvedExistingFileURL(path: path)
        guard let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else {
            throw ExistingFileOpenerError.appNotFound(bundleID)
        }

        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            NSWorkspace.shared.open(
                [fileURL],
                withApplicationAt: appURL,
                configuration: configuration
            ) { _, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            }
        }
    }
}
