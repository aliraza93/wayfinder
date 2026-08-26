import Domain
import Foundation

// MARK: - Document

public struct WorkflowConfigDocument: Equatable, Sendable {
    public var schemaVersion: Int
    public var workflows: [Workflow]

    public init(schemaVersion: Int = SchemaVersion.current, workflows: [Workflow]) {
        self.schemaVersion = schemaVersion
        self.workflows = workflows
    }
}

// MARK: - Strict coding helpers

struct StrictCodingKey: CodingKey, Hashable {
    var stringValue: String
    var intValue: Int? { nil }

    init(stringValue: String) {
        self.stringValue = stringValue
    }

    init?(intValue: Int) {
        return nil
    }
}

enum StrictJSON {
    static func requireKeys(
        _ container: KeyedDecodingContainer<StrictCodingKey>,
        allowed: Set<String>,
        path: String
    ) throws {
        for key in container.allKeys {
            if !allowed.contains(key.stringValue) {
                throw ConfigError.unknownKey(path: path, key: key.stringValue)
            }
        }
    }

    static func decodeString(
        _ container: KeyedDecodingContainer<StrictCodingKey>,
        _ key: String,
        path: String
    ) throws -> String {
        let codingKey = StrictCodingKey(stringValue: key)
        guard container.contains(codingKey) else {
            throw ConfigError.missingKey(path: path, key: key)
        }
        return try container.decode(String.self, forKey: codingKey)
    }

    static func decodeInt(
        _ container: KeyedDecodingContainer<StrictCodingKey>,
        _ key: String,
        path: String
    ) throws -> Int {
        let codingKey = StrictCodingKey(stringValue: key)
        guard container.contains(codingKey) else {
            throw ConfigError.missingKey(path: path, key: key)
        }
        return try container.decode(Int.self, forKey: codingKey)
    }

    static func decodeDouble(
        _ container: KeyedDecodingContainer<StrictCodingKey>,
        _ key: String,
        path: String
    ) throws -> Double {
        let codingKey = StrictCodingKey(stringValue: key)
        guard container.contains(codingKey) else {
            throw ConfigError.missingKey(path: path, key: key)
        }
        return try container.decode(Double.self, forKey: codingKey)
    }

    static func decodeBool(
        _ container: KeyedDecodingContainer<StrictCodingKey>,
        _ key: String,
        path: String
    ) throws -> Bool {
        let codingKey = StrictCodingKey(stringValue: key)
        guard container.contains(codingKey) else {
            throw ConfigError.missingKey(path: path, key: key)
        }
        return try container.decode(Bool.self, forKey: codingKey)
    }

    static func decodeIfPresentDouble(
        _ container: KeyedDecodingContainer<StrictCodingKey>,
        _ key: String
    ) throws -> Double? {
        let codingKey = StrictCodingKey(stringValue: key)
        guard container.contains(codingKey), try !container.decodeNil(forKey: codingKey) else {
            return nil
        }
        return try container.decode(Double.self, forKey: codingKey)
    }

    static func decodeIfPresentBool(
        _ container: KeyedDecodingContainer<StrictCodingKey>,
        _ key: String
    ) throws -> Bool? {
        let codingKey = StrictCodingKey(stringValue: key)
        guard container.contains(codingKey), try !container.decodeNil(forKey: codingKey) else {
            return nil
        }
        return try container.decode(Bool.self, forKey: codingKey)
    }

    static func decodeIfPresentInt(
        _ container: KeyedDecodingContainer<StrictCodingKey>,
        _ key: String
    ) throws -> Int? {
        let codingKey = StrictCodingKey(stringValue: key)
        guard container.contains(codingKey), try !container.decodeNil(forKey: codingKey) else {
            return nil
        }
        return try container.decode(Int.self, forKey: codingKey)
    }
}

// MARK: - WorkflowConfigDocument

extension WorkflowConfigDocument: Codable {
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: StrictCodingKey.self)
        try StrictJSON.requireKeys(container, allowed: ["schemaVersion", "workflows"], path: "$")
        schemaVersion = try StrictJSON.decodeInt(container, "schemaVersion", path: "$")
        let workflowsKey = StrictCodingKey(stringValue: "workflows")
        guard container.contains(workflowsKey) else {
            throw ConfigError.missingKey(path: "$", key: "workflows")
        }
        workflows = try container.decode([Workflow].self, forKey: workflowsKey)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: StrictCodingKey.self)
        try container.encode(schemaVersion, forKey: StrictCodingKey(stringValue: "schemaVersion"))
        try container.encode(workflows, forKey: StrictCodingKey(stringValue: "workflows"))
    }
}

// MARK: - Workflow

extension Workflow: Codable {
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: StrictCodingKey.self)
        try StrictJSON.requireKeys(
            container,
            allowed: ["name", "targets", "steps", "loop", "reviewFilePaths", "review"],
            path: "workflow"
        )
        let name = try StrictJSON.decodeString(container, "name", path: "workflow")
        let targets = try container.decode(
            [TargetApp].self,
            forKey: StrictCodingKey(stringValue: "targets")
        )
        let steps = try container.decode([Step].self, forKey: StrictCodingKey(stringValue: "steps"))
        let loop = try container.decode(
            LoopSettings.self,
            forKey: StrictCodingKey(stringValue: "loop")
        )
        let reviewFilePaths = try container.decodeIfPresent(
            [String].self,
            forKey: StrictCodingKey(stringValue: "reviewFilePaths")
        ) ?? []
        var review = try container.decodeIfPresent(
            ReviewWorkspaceSettings.self,
            forKey: StrictCodingKey(stringValue: "review")
        ) ?? .default
        if review.filePaths.isEmpty, !reviewFilePaths.isEmpty {
            review.filePaths = reviewFilePaths
        }
        review.normalize()
        self.init(
            name: name,
            targets: targets,
            steps: steps,
            loop: loop,
            reviewFilePaths: reviewFilePaths,
            review: review
        )
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: StrictCodingKey.self)
        try container.encode(name, forKey: StrictCodingKey(stringValue: "name"))
        try container.encode(targets, forKey: StrictCodingKey(stringValue: "targets"))
        try container.encode(steps, forKey: StrictCodingKey(stringValue: "steps"))
        try container.encode(loop, forKey: StrictCodingKey(stringValue: "loop"))
        let paths = review.filePaths.isEmpty ? reviewFilePaths : review.filePaths
        if !paths.isEmpty {
            try container.encode(paths, forKey: StrictCodingKey(stringValue: "reviewFilePaths"))
        }
        try container.encode(review, forKey: StrictCodingKey(stringValue: "review"))
    }
}

// MARK: - LoopSettings

extension LoopSettings: Codable {
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: StrictCodingKey.self)
        try StrictJSON.requireKeys(
            container,
            allowed: ["enabled", "maxIterations", "maxDurationSeconds", "untilStopped", "shuffleSteps"],
            path: "loop"
        )
        let enabled = try StrictJSON.decodeBool(container, "enabled", path: "loop")
        let maxIterations = try StrictJSON.decodeInt(container, "maxIterations", path: "loop")
        let maxDurationSeconds = try StrictJSON.decodeIfPresentDouble(
            container,
            "maxDurationSeconds"
        )
        let untilStopped = try StrictJSON.decodeIfPresentBool(container, "untilStopped") ?? false
        let shuffleSteps = try StrictJSON.decodeIfPresentBool(container, "shuffleSteps") ?? false
        self.init(
            enabled: enabled,
            maxIterations: maxIterations,
            maxDurationSeconds: maxDurationSeconds,
            untilStopped: untilStopped,
            shuffleSteps: shuffleSteps
        )
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: StrictCodingKey.self)
        try container.encode(enabled, forKey: StrictCodingKey(stringValue: "enabled"))
        try container.encode(maxIterations, forKey: StrictCodingKey(stringValue: "maxIterations"))
        try container.encodeIfPresent(
            maxDurationSeconds,
            forKey: StrictCodingKey(stringValue: "maxDurationSeconds")
        )
        if untilStopped {
            try container.encode(untilStopped, forKey: StrictCodingKey(stringValue: "untilStopped"))
        }
        if shuffleSteps {
            try container.encode(shuffleSteps, forKey: StrictCodingKey(stringValue: "shuffleSteps"))
        }
    }
}

// MARK: - Step

extension Step: Codable {
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: StrictCodingKey.self)
        try StrictJSON.requireKeys(
            container,
            allowed: ["action", "timeoutSeconds", "retryPolicy", "onError"],
            path: "step"
        )
        let action = try container.decode(
            ActionKind.self,
            forKey: StrictCodingKey(stringValue: "action")
        )
        let timeoutSeconds = try StrictJSON.decodeDouble(container, "timeoutSeconds", path: "step")
        let retryPolicy = try container.decode(
            RetryPolicy.self,
            forKey: StrictCodingKey(stringValue: "retryPolicy")
        )
        let onError = try container.decode(
            OnErrorBehavior.self,
            forKey: StrictCodingKey(stringValue: "onError")
        )
        self.init(
            action: action,
            timeoutSeconds: timeoutSeconds,
            retryPolicy: retryPolicy,
            onError: onError
        )
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: StrictCodingKey.self)
        try container.encode(action, forKey: StrictCodingKey(stringValue: "action"))
        try container.encode(timeoutSeconds, forKey: StrictCodingKey(stringValue: "timeoutSeconds"))
        try container.encode(retryPolicy, forKey: StrictCodingKey(stringValue: "retryPolicy"))
        try container.encode(onError, forKey: StrictCodingKey(stringValue: "onError"))
    }
}

// MARK: - RetryPolicy

extension RetryPolicy: Codable {
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: StrictCodingKey.self)
        try StrictJSON.requireKeys(container, allowed: ["maxRetries"], path: "retryPolicy")
        let maxRetries = try StrictJSON.decodeInt(container, "maxRetries", path: "retryPolicy")
        self.init(maxRetries: maxRetries)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: StrictCodingKey.self)
        try container.encode(maxRetries, forKey: StrictCodingKey(stringValue: "maxRetries"))
    }
}

// MARK: - OnErrorBehavior

extension OnErrorBehavior: Codable {
    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let raw = try container.decode(String.self)
        switch raw {
        case "retry": self = .retry
        case "skip": self = .skip
        case "abort": self = .abort
        default:
            throw ConfigError.invalidValue(path: "onError", detail: "unknown value \(raw)")
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .retry: try container.encode("retry")
        case .skip: try container.encode("skip")
        case .abort: try container.encode("abort")
        }
    }
}

// MARK: - TargetApp

extension TargetApp: Codable {
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: StrictCodingKey.self)
        try StrictJSON.requireKeys(
            container,
            allowed: ["bundleID", "classification"],
            path: "target"
        )
        let bundleID = try StrictJSON.decodeString(container, "bundleID", path: "target")
        let classification = try container.decode(
            TargetAppClass.self,
            forKey: StrictCodingKey(stringValue: "classification")
        )
        self.init(bundleID: bundleID, classification: classification)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: StrictCodingKey.self)
        try container.encode(bundleID, forKey: StrictCodingKey(stringValue: "bundleID"))
        try container.encode(classification, forKey: StrictCodingKey(stringValue: "classification"))
    }
}

// MARK: - TargetAppClass

extension TargetAppClass: Codable {
    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let raw = try container.decode(String.self)
        switch raw {
        case "browser": self = .browser
        case "editor": self = .editor
        case "finder": self = .finder
        case "generic": self = .generic
        default:
            throw ConfigError.invalidValue(path: "classification", detail: "unknown value \(raw)")
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .browser: try container.encode("browser")
        case .editor: try container.encode("editor")
        case .finder: try container.encode("finder")
        case .generic: try container.encode("generic")
        }
    }
}

// MARK: - ActionKind (pinned discriminator encoding)

extension ActionKind: Codable {
    /// Pinned JSON shapes use a `"type"` discriminator. Example for scroll:
    /// `{"type":"scroll","direction":"down","amount":3}`
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: StrictCodingKey.self)
        let type = try StrictJSON.decodeString(container, "type", path: "action")

        switch type {
        case "activateApp":
            try StrictJSON.requireKeys(container, allowed: ["type", "bundleID"], path: "action")
            let bundleID = try StrictJSON.decodeString(container, "bundleID", path: "action")
            self = .activateApp(bundleID: bundleID)

        case "switchWindow":
            try StrictJSON.requireKeys(container, allowed: ["type", "direction"], path: "action")
            let direction = try container.decode(
                WindowDirection.self,
                forKey: StrictCodingKey(stringValue: "direction")
            )
            self = .switchWindow(direction: direction)

        case "scroll":
            try StrictJSON.requireKeys(
                container,
                allowed: ["type", "direction", "amount"],
                path: "action"
            )
            let direction = try container.decode(
                ScrollDirection.self,
                forKey: StrictCodingKey(stringValue: "direction")
            )
            let amount = try StrictJSON.decodeInt(container, "amount", path: "action")
            self = .scroll(direction: direction, amount: amount)

        case "pageNavigate":
            try StrictJSON.requireKeys(container, allowed: ["type", "move"], path: "action")
            let move = try container.decode(
                PageMove.self,
                forKey: StrictCodingKey(stringValue: "move")
            )
            self = .pageNavigate(move)

        case "arrowNavigate":
            try StrictJSON.requireKeys(
                container,
                allowed: ["type", "direction", "presses", "intervalSeconds"],
                path: "action"
            )
            let direction = try container.decode(
                ArrowDirection.self,
                forKey: StrictCodingKey(stringValue: "direction")
            )
            let presses = try StrictJSON.decodeIfPresentInt(container, "presses") ?? 1
            let intervalSeconds = try StrictJSON.decodeIfPresentDouble(container, "intervalSeconds") ?? 0
            self = .arrowNavigate(
                direction: direction,
                presses: presses,
                intervalSeconds: intervalSeconds
            )

        case "switchTab":
            try StrictJSON.requireKeys(container, allowed: ["type", "direction"], path: "action")
            let direction = try container.decode(
                WindowDirection.self,
                forKey: StrictCodingKey(stringValue: "direction")
            )
            self = .switchTab(direction: direction)

        case "highlightNavigate":
            try StrictJSON.requireKeys(container, allowed: ["type", "direction"], path: "action")
            let direction = try container.decode(
                ArrowDirection.self,
                forKey: StrictCodingKey(stringValue: "direction")
            )
            self = .highlightNavigate(direction: direction)

        case "contentClick":
            try StrictJSON.requireKeys(container, allowed: ["type"], path: "action")
            self = .contentClick

        case "explorerFileSwitch":
            try StrictJSON.requireKeys(container, allowed: ["type", "direction"], path: "action")
            let direction = try container.decode(
                WindowDirection.self,
                forKey: StrictCodingKey(stringValue: "direction")
            )
            self = .explorerFileSwitch(direction: direction)

        case "inspectWebPage":
            try StrictJSON.requireKeys(container, allowed: ["type"], path: "action")
            self = .inspectWebPage

        case "activateWebNavTarget":
            try StrictJSON.requireKeys(
                container,
                allowed: ["type", "identity", "x", "y"],
                path: "action"
            )
            let identity = try StrictJSON.decodeString(container, "identity", path: "action")
            let x = try StrictJSON.decodeDouble(container, "x", path: "action")
            let y = try StrictJSON.decodeDouble(container, "y", path: "action")
            self = .activateWebNavTarget(identity: identity, x: x, y: y)

        case "browserBack":
            try StrictJSON.requireKeys(container, allowed: ["type"], path: "action")
            self = .browserBack

        case "openExistingFile":
            try StrictJSON.requireKeys(container, allowed: ["type", "path"], path: "action")
            let path = try StrictJSON.decodeString(container, "path", path: "action")
            self = .openExistingFile(path: path)

        case "wait":
            try StrictJSON.requireKeys(container, allowed: ["type", "seconds"], path: "action")
            let seconds = try StrictJSON.decodeDouble(container, "seconds", path: "action")
            self = .wait(seconds: seconds)

        case "returnToPrevious":
            try StrictJSON.requireKeys(container, allowed: ["type"], path: "action")
            self = .returnToPrevious

        default:
            throw ConfigError.invalidValue(path: "action.type", detail: "unknown type \(type)")
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: StrictCodingKey.self)
        switch self {
        case .activateApp(let bundleID):
            try container.encode("activateApp", forKey: StrictCodingKey(stringValue: "type"))
            try container.encode(bundleID, forKey: StrictCodingKey(stringValue: "bundleID"))

        case .switchWindow(let direction):
            try container.encode("switchWindow", forKey: StrictCodingKey(stringValue: "type"))
            try container.encode(direction, forKey: StrictCodingKey(stringValue: "direction"))

        case .switchTab(let direction):
            try container.encode("switchTab", forKey: StrictCodingKey(stringValue: "type"))
            try container.encode(direction, forKey: StrictCodingKey(stringValue: "direction"))

        case .scroll(let direction, let amount):
            try container.encode("scroll", forKey: StrictCodingKey(stringValue: "type"))
            try container.encode(direction, forKey: StrictCodingKey(stringValue: "direction"))
            try container.encode(amount, forKey: StrictCodingKey(stringValue: "amount"))

        case .pageNavigate(let move):
            try container.encode("pageNavigate", forKey: StrictCodingKey(stringValue: "type"))
            try container.encode(move, forKey: StrictCodingKey(stringValue: "move"))

        case .arrowNavigate(let direction, let presses, let intervalSeconds):
            try container.encode("arrowNavigate", forKey: StrictCodingKey(stringValue: "type"))
            try container.encode(direction, forKey: StrictCodingKey(stringValue: "direction"))
            try container.encode(presses, forKey: StrictCodingKey(stringValue: "presses"))
            try container.encode(intervalSeconds, forKey: StrictCodingKey(stringValue: "intervalSeconds"))

        case .highlightNavigate(let direction):
            try container.encode("highlightNavigate", forKey: StrictCodingKey(stringValue: "type"))
            try container.encode(direction, forKey: StrictCodingKey(stringValue: "direction"))

        case .contentClick:
            try container.encode("contentClick", forKey: StrictCodingKey(stringValue: "type"))

        case .explorerFileSwitch(let direction):
            try container.encode("explorerFileSwitch", forKey: StrictCodingKey(stringValue: "type"))
            try container.encode(direction, forKey: StrictCodingKey(stringValue: "direction"))

        case .inspectWebPage:
            try container.encode("inspectWebPage", forKey: StrictCodingKey(stringValue: "type"))

        case .activateWebNavTarget(let identity, let x, let y):
            try container.encode("activateWebNavTarget", forKey: StrictCodingKey(stringValue: "type"))
            try container.encode(identity, forKey: StrictCodingKey(stringValue: "identity"))
            try container.encode(x, forKey: StrictCodingKey(stringValue: "x"))
            try container.encode(y, forKey: StrictCodingKey(stringValue: "y"))

        case .browserBack:
            try container.encode("browserBack", forKey: StrictCodingKey(stringValue: "type"))

        case .openExistingFile(let path):
            try container.encode("openExistingFile", forKey: StrictCodingKey(stringValue: "type"))
            try container.encode(path, forKey: StrictCodingKey(stringValue: "path"))

        case .wait(let seconds):
            try container.encode("wait", forKey: StrictCodingKey(stringValue: "type"))
            try container.encode(seconds, forKey: StrictCodingKey(stringValue: "seconds"))

        case .returnToPrevious:
            try container.encode("returnToPrevious", forKey: StrictCodingKey(stringValue: "type"))
        }
    }
}

// MARK: - Direction / page enums

extension WindowDirection: Codable {
    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let raw = try container.decode(String.self)
        switch raw {
        case "next": self = .next
        case "previous": self = .previous
        default:
            throw ConfigError.invalidValue(path: "direction", detail: "unknown value \(raw)")
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .next: try container.encode("next")
        case .previous: try container.encode("previous")
        }
    }
}

extension ScrollDirection: Codable {
    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let raw = try container.decode(String.self)
        switch raw {
        case "up": self = .up
        case "down": self = .down
        case "left": self = .left
        case "right": self = .right
        default:
            throw ConfigError.invalidValue(path: "direction", detail: "unknown value \(raw)")
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .up: try container.encode("up")
        case .down: try container.encode("down")
        case .left: try container.encode("left")
        case .right: try container.encode("right")
        }
    }
}

extension ArrowDirection: Codable {
    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let raw = try container.decode(String.self)
        switch raw {
        case "up": self = .up
        case "down": self = .down
        case "left": self = .left
        case "right": self = .right
        default:
            throw ConfigError.invalidValue(path: "direction", detail: "unknown value \(raw)")
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .up: try container.encode("up")
        case .down: try container.encode("down")
        case .left: try container.encode("left")
        case .right: try container.encode("right")
        }
    }
}

extension PageMove: Codable {
    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let raw = try container.decode(String.self)
        switch raw {
        case "pageUp": self = .pageUp
        case "pageDown": self = .pageDown
        case "home": self = .home
        case "end": self = .end
        default:
            throw ConfigError.invalidValue(path: "move", detail: "unknown value \(raw)")
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .pageUp: try container.encode("pageUp")
        case .pageDown: try container.encode("pageDown")
        case .home: try container.encode("home")
        case .end: try container.encode("end")
        }
    }
}

// MARK: - ReviewWorkspaceSettings

extension ReviewWorkspaceSettings: Codable {
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: StrictCodingKey.self)
        try StrictJSON.requireKeys(
            container,
            allowed: [
                "workspacePath", "filePaths", "chromeTabLabels",
                "dwellMinSeconds", "dwellMaxSeconds",
                "speed", "customIntervalSeconds", "targetOrder", "loopTargets",
                "discoverRunningApps", "discovery", "refreshTargetsBetweenDwells",
                "chrome",
            ],
            path: "review"
        )
        let discovery = try container.decodeIfPresent(
            DiscoveryScope.self,
            forKey: StrictCodingKey(stringValue: "discovery")
        ) ?? .default
        let chrome = try container.decodeIfPresent(
            ChromeNavigationSettings.self,
            forKey: StrictCodingKey(stringValue: "chrome")
        ) ?? .default
        var settings = ReviewWorkspaceSettings(
            workspacePath: (try? container.decode(String.self, forKey: StrictCodingKey(stringValue: "workspacePath"))) ?? "",
            filePaths: try container.decodeIfPresent([String].self, forKey: StrictCodingKey(stringValue: "filePaths")) ?? [],
            chromeTabLabels: try container.decodeIfPresent([String].self, forKey: StrictCodingKey(stringValue: "chromeTabLabels")) ?? [],
            dwellMinSeconds: try StrictJSON.decodeIfPresentDouble(container, "dwellMinSeconds") ?? 30,
            dwellMaxSeconds: try StrictJSON.decodeIfPresentDouble(container, "dwellMaxSeconds") ?? 180,
            speed: (try? container.decode(NavigationSpeedPreset.self, forKey: StrictCodingKey(stringValue: "speed"))) ?? .normal,
            customIntervalSeconds: try StrictJSON.decodeIfPresentDouble(container, "customIntervalSeconds") ?? 0.35,
            targetOrder: (try? container.decode(ReviewTargetOrder.self, forKey: StrictCodingKey(stringValue: "targetOrder"))) ?? .sequential,
            loopTargets: try StrictJSON.decodeIfPresentBool(container, "loopTargets") ?? true,
            discoverRunningApps: try StrictJSON.decodeIfPresentBool(container, "discoverRunningApps") ?? false,
            discovery: discovery,
            refreshTargetsBetweenDwells: try StrictJSON.decodeIfPresentBool(container, "refreshTargetsBetweenDwells") ?? false,
            chrome: chrome
        )
        settings.normalize()
        self = settings
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: StrictCodingKey.self)
        try container.encode(workspacePath, forKey: StrictCodingKey(stringValue: "workspacePath"))
        try container.encode(filePaths, forKey: StrictCodingKey(stringValue: "filePaths"))
        try container.encode(chromeTabLabels, forKey: StrictCodingKey(stringValue: "chromeTabLabels"))
        try container.encode(dwellMinSeconds, forKey: StrictCodingKey(stringValue: "dwellMinSeconds"))
        try container.encode(dwellMaxSeconds, forKey: StrictCodingKey(stringValue: "dwellMaxSeconds"))
        try container.encode(speed, forKey: StrictCodingKey(stringValue: "speed"))
        try container.encode(customIntervalSeconds, forKey: StrictCodingKey(stringValue: "customIntervalSeconds"))
        try container.encode(targetOrder, forKey: StrictCodingKey(stringValue: "targetOrder"))
        try container.encode(loopTargets, forKey: StrictCodingKey(stringValue: "loopTargets"))
        try container.encode(discoverRunningApps, forKey: StrictCodingKey(stringValue: "discoverRunningApps"))
        try container.encode(discovery, forKey: StrictCodingKey(stringValue: "discovery"))
        try container.encode(refreshTargetsBetweenDwells, forKey: StrictCodingKey(stringValue: "refreshTargetsBetweenDwells"))
        try container.encode(chrome, forKey: StrictCodingKey(stringValue: "chrome"))
    }
}

extension DiscoveryScope: Codable {
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: StrictCodingKey.self)
        try StrictJSON.requireKeys(
            container,
            allowed: [
                "includeEditors", "includeBrowsers", "includeFinder",
                "includePreview", "includeOther",
            ],
            path: "review.discovery"
        )
        self.init(
            includeEditors: try StrictJSON.decodeIfPresentBool(container, "includeEditors") ?? true,
            includeBrowsers: try StrictJSON.decodeIfPresentBool(container, "includeBrowsers") ?? true,
            includeFinder: try StrictJSON.decodeIfPresentBool(container, "includeFinder") ?? false,
            includePreview: try StrictJSON.decodeIfPresentBool(container, "includePreview") ?? false,
            includeOther: try StrictJSON.decodeIfPresentBool(container, "includeOther") ?? false
        )
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: StrictCodingKey.self)
        try container.encode(includeEditors, forKey: StrictCodingKey(stringValue: "includeEditors"))
        try container.encode(includeBrowsers, forKey: StrictCodingKey(stringValue: "includeBrowsers"))
        try container.encode(includeFinder, forKey: StrictCodingKey(stringValue: "includeFinder"))
        try container.encode(includePreview, forKey: StrictCodingKey(stringValue: "includePreview"))
        try container.encode(includeOther, forKey: StrictCodingKey(stringValue: "includeOther"))
    }
}

extension NavigationSpeedPreset: Codable {}
extension ReviewTargetOrder: Codable {}

extension ChromeNavigationSettings: Codable {
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: StrictCodingKey.self)
        try StrictJSON.requireKeys(
            container,
            allowed: [
                "enabled", "profile", "allowedDomains", "blockedDomains", "externalDomainPolicy",
                "currentDomainOnly", "allowExternalLinks",
                "maxDepth", "maxPages", "maxTimePerPageSeconds", "maxScrollsPerPage",
                "crawlDocumentation", "crawlSourceFiles", "crawlRepositoryDirectories",
                "crawlIssues", "githubStrategy", "selectedDirectories",
                "preferredLinkKeywords", "excludedPathPrefixes",
            ],
            path: "review.chrome"
        )
        var settings = ChromeNavigationSettings(
            enabled: try StrictJSON.decodeIfPresentBool(container, "enabled") ?? true,
            profile: (try? container.decode(
                ChromeNavigationProfile.self,
                forKey: StrictCodingKey(stringValue: "profile")
            )) ?? .generalWebsite,
            allowedDomains: try container.decodeIfPresent(
                [String].self,
                forKey: StrictCodingKey(stringValue: "allowedDomains")
            ) ?? [],
            blockedDomains: try container.decodeIfPresent(
                [String].self,
                forKey: StrictCodingKey(stringValue: "blockedDomains")
            ) ?? [],
            externalDomainPolicy: (try? container.decode(
                ChromeExternalDomainPolicy.self,
                forKey: StrictCodingKey(stringValue: "externalDomainPolicy")
            )) ?? .blocked,
            currentDomainOnly: try StrictJSON.decodeIfPresentBool(container, "currentDomainOnly") ?? true,
            allowExternalLinks: try StrictJSON.decodeIfPresentBool(container, "allowExternalLinks") ?? false,
            maxDepth: try StrictJSON.decodeIfPresentInt(container, "maxDepth") ?? 3,
            maxPages: try StrictJSON.decodeIfPresentInt(container, "maxPages") ?? 20,
            maxTimePerPageSeconds: try StrictJSON.decodeIfPresentDouble(container, "maxTimePerPageSeconds") ?? 180,
            maxScrollsPerPage: try StrictJSON.decodeIfPresentInt(container, "maxScrollsPerPage") ?? 40,
            crawlDocumentation: try StrictJSON.decodeIfPresentBool(container, "crawlDocumentation") ?? true,
            crawlSourceFiles: try StrictJSON.decodeIfPresentBool(container, "crawlSourceFiles") ?? true,
            crawlRepositoryDirectories: try StrictJSON.decodeIfPresentBool(container, "crawlRepositoryDirectories") ?? true,
            crawlIssues: try StrictJSON.decodeIfPresentBool(container, "crawlIssues") ?? false,
            githubStrategy: (try? container.decode(
                GitHubCrawlStrategy.self,
                forKey: StrictCodingKey(stringValue: "githubStrategy")
            )) ?? .breadthFirst,
            selectedDirectories: try container.decodeIfPresent(
                [String].self,
                forKey: StrictCodingKey(stringValue: "selectedDirectories")
            ) ?? ["app/", "src/", "routes/", "tests/"],
            preferredLinkKeywords: try container.decodeIfPresent(
                [String].self,
                forKey: StrictCodingKey(stringValue: "preferredLinkKeywords")
            ) ?? [],
            excludedPathPrefixes: try container.decodeIfPresent(
                [String].self,
                forKey: StrictCodingKey(stringValue: "excludedPathPrefixes")
            ) ?? []
        )
        settings.normalize()
        self = settings
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: StrictCodingKey.self)
        try container.encode(enabled, forKey: StrictCodingKey(stringValue: "enabled"))
        try container.encode(profile, forKey: StrictCodingKey(stringValue: "profile"))
        try container.encode(allowedDomains, forKey: StrictCodingKey(stringValue: "allowedDomains"))
        try container.encode(blockedDomains, forKey: StrictCodingKey(stringValue: "blockedDomains"))
        try container.encode(externalDomainPolicy, forKey: StrictCodingKey(stringValue: "externalDomainPolicy"))
        try container.encode(currentDomainOnly, forKey: StrictCodingKey(stringValue: "currentDomainOnly"))
        try container.encode(allowExternalLinks, forKey: StrictCodingKey(stringValue: "allowExternalLinks"))
        try container.encode(maxDepth, forKey: StrictCodingKey(stringValue: "maxDepth"))
        try container.encode(maxPages, forKey: StrictCodingKey(stringValue: "maxPages"))
        try container.encode(maxTimePerPageSeconds, forKey: StrictCodingKey(stringValue: "maxTimePerPageSeconds"))
        try container.encode(maxScrollsPerPage, forKey: StrictCodingKey(stringValue: "maxScrollsPerPage"))
        try container.encode(crawlDocumentation, forKey: StrictCodingKey(stringValue: "crawlDocumentation"))
        try container.encode(crawlSourceFiles, forKey: StrictCodingKey(stringValue: "crawlSourceFiles"))
        try container.encode(crawlRepositoryDirectories, forKey: StrictCodingKey(stringValue: "crawlRepositoryDirectories"))
        try container.encode(crawlIssues, forKey: StrictCodingKey(stringValue: "crawlIssues"))
        try container.encode(githubStrategy, forKey: StrictCodingKey(stringValue: "githubStrategy"))
        try container.encode(selectedDirectories, forKey: StrictCodingKey(stringValue: "selectedDirectories"))
        try container.encode(preferredLinkKeywords, forKey: StrictCodingKey(stringValue: "preferredLinkKeywords"))
        try container.encode(excludedPathPrefixes, forKey: StrictCodingKey(stringValue: "excludedPathPrefixes"))
    }
}
