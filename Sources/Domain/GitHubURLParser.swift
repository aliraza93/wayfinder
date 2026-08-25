import Foundation

/// Pure GitHub URL path heuristics (no network).
public enum GitHubURLParser: Sendable {
    public struct RepoPath: Equatable, Sendable {
        public var owner: String
        public var repo: String
        public var kind: WebPageKind
        public var ref: String?
        public var pathInsideRepo: String

        public init(
            owner: String,
            repo: String,
            kind: WebPageKind,
            ref: String? = nil,
            pathInsideRepo: String = ""
        ) {
            self.owner = owner
            self.repo = repo
            self.kind = kind
            self.ref = ref
            self.pathInsideRepo = pathInsideRepo
        }
    }

    public static func pageKind(for url: String) -> WebPageKind {
        parse(url)?.kind ?? inferNonGitHub(url)
    }

    public static func parse(_ url: String) -> RepoPath? {
        let normalized = URLNormalizer.normalize(url)
        guard let comps = URLComponents(string: normalized),
              let host = comps.host?.lowercased(),
              host == "github.com" || host.hasSuffix(".github.com")
        else {
            return nil
        }
        let parts = comps.path.split(separator: "/").map(String.init)
        guard parts.count >= 2 else {
            return RepoPath(owner: "", repo: "", kind: .githubOther)
        }
        let owner = parts[0]
        let repo = parts[1]
        if parts.count == 2 {
            return RepoPath(owner: owner, repo: repo, kind: .githubRepoRoot)
        }
        let section = parts[2].lowercased()
        switch section {
        case "tree":
            let ref = parts.count > 3 ? parts[3] : nil
            let rest = parts.count > 4 ? parts[4...].joined(separator: "/") : ""
            return RepoPath(owner: owner, repo: repo, kind: .githubTree, ref: ref, pathInsideRepo: rest)
        case "blob":
            let ref = parts.count > 3 ? parts[3] : nil
            let rest = parts.count > 4 ? parts[4...].joined(separator: "/") : ""
            return RepoPath(owner: owner, repo: repo, kind: .githubBlob, ref: ref, pathInsideRepo: rest)
        case "issues", "pulls", "pull":
            return RepoPath(owner: owner, repo: repo, kind: .githubIssues, pathInsideRepo: parts.dropFirst(2).joined(separator: "/"))
        default:
            return RepoPath(owner: owner, repo: repo, kind: .githubOther, pathInsideRepo: parts.dropFirst(2).joined(separator: "/"))
        }
    }

    public static func isSourceFilePath(_ path: String) -> Bool {
        let lower = path.lowercased()
        let exts = [
            ".swift", ".ts", ".tsx", ".js", ".jsx", ".py", ".rb", ".go", ".rs",
            ".java", ".kt", ".cs", ".php", ".c", ".h", ".cpp", ".m", ".mm",
            ".css", ".scss", ".html", ".json", ".yml", ".yaml", ".toml", ".md",
            ".sh", ".sql",
        ]
        return exts.contains { lower.hasSuffix($0) }
    }

    private static func inferNonGitHub(_ url: String) -> WebPageKind {
        let lower = url.lowercased()
        if lower.contains("/docs") || lower.contains("documentation") || lower.contains("developer.") {
            return .documentation
        }
        return .generic
    }
}
