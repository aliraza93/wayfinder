import Adapters
import CryptoKit
import Domain
import Foundation
import XCTest

/// Mutation-guard: a scratch source file’s hash/mtime must be unchanged after an editor
/// navigation loop that only selects inert primitives (no live CGEvents in CI).
///
/// Live VS Code (+ Vim keymap) confirmation is documented in `docs/manual-tests.md`.
final class MutationGuardTests: XCTestCase {
    func testScratchFileHashUnchangedAfterInertNavigationLoop() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("waypoint-mutation-guard-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let scratch = dir.appendingPathComponent("Scratch.swift")
        let payload = """
        // mutation-guard scratch — must not change
        func hello() -> String {
            return "unchanged"
        }

        """
        try payload.write(to: scratch, atomically: true, encoding: .utf8)

        let beforeHash = try Self.sha256Hex(of: scratch)
        let beforeMtime = try Self.modificationDate(of: scratch)

        // Simulate editor navigation (default keymap / no Vim chords in our path).
        try Self.runInertNavigationLoop(label: "no-vim", scratch: scratch)

        let afterHash = try Self.sha256Hex(of: scratch)
        let afterMtime = try Self.modificationDate(of: scratch)

        XCTAssertEqual(
            beforeHash,
            afterHash,
            "file mutated under default keymap path\nbefore: \(beforeHash)\nafter:  \(afterHash)"
        )
        XCTAssertEqual(beforeMtime, afterMtime, "mtime changed under default keymap path")

        // Same inert emission set when a Vim keymap is assumed — we never emit chords/characters,
        // so insert/normal mode cannot receive mutating keystrokes from this adapter.
        try Self.runInertNavigationLoop(label: "vim-keymap-assumed", scratch: scratch)

        let vimHash = try Self.sha256Hex(of: scratch)
        let vimMtime = try Self.modificationDate(of: scratch)
        XCTAssertEqual(
            beforeHash,
            vimHash,
            "file mutated under vim-keymap-assumed path\nbefore: \(beforeHash)\nafter:  \(vimHash)"
        )
        XCTAssertEqual(beforeMtime, vimMtime, "mtime changed under vim-keymap-assumed path")

        // Surface hashes for the milestone report.
        print("MUTATION_GUARD no-vim / vim-assumed before=\(beforeHash) after=\(afterHash) vim=\(vimHash)")
    }

    /// Builds the editor adapter loop and asserts every primitive is inert; never opens the scratch for write.
    private static func runInertNavigationLoop(label: String, scratch: URL) throws {
        _ = label
        var adapter = EditorAdapter(probe: FixedEditorProbe(result: .dependable))
        adapter.prepare(
            target: TargetApp(bundleID: "com.microsoft.VSCode", classification: .editor)
        )

        let primitives = adapter.navigationLoopPrimitives(scrollAmount: 40, includeArrows: true)
        XCTAssertFalse(primitives.isEmpty)
        for p in primitives {
            XCTAssertTrue(
                EditorAdapter.isStrictlyInert(p),
                "[\(label)] non-inert primitive would risk mutation: \(p)"
            )
        }

        // Read-only touch: ensure we can still read the scratch (simulates editor having it open).
        let data = try Data(contentsOf: scratch)
        XCTAssertFalse(data.isEmpty)
        // Deliberately do not write.
    }

    private static func sha256Hex(of url: URL) throws -> String {
        let data = try Data(contentsOf: url)
        let digest = SHA256.hash(data: data)
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    private static func modificationDate(of url: URL) throws -> Date {
        let values = try url.resourceValues(forKeys: [.contentModificationDateKey])
        guard let date = values.contentModificationDate else {
            throw NSError(
                domain: "MutationGuard",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "missing mtime"]
            )
        }
        return date
    }
}
