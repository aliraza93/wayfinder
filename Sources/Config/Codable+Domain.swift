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
            allowed: ["name", "targets", "steps", "loop"],
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
        self.init(name: name, targets: targets, steps: steps, loop: loop)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: StrictCodingKey.self)
        try container.encode(name, forKey: StrictCodingKey(stringValue: "name"))
        try container.encode(targets, forKey: StrictCodingKey(stringValue: "targets"))
        try container.encode(steps, forKey: StrictCodingKey(stringValue: "steps"))
        try container.encode(loop, forKey: StrictCodingKey(stringValue: "loop"))
    }
}

// MARK: - LoopSettings

extension LoopSettings: Codable {
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: StrictCodingKey.self)
        try StrictJSON.requireKeys(
            container,
            allowed: ["enabled", "maxIterations", "maxDurationSeconds"],
            path: "loop"
        )
        let enabled = try StrictJSON.decodeBool(container, "enabled", path: "loop")
        let maxIterations = try StrictJSON.decodeInt(container, "maxIterations", path: "loop")
        let maxDurationSeconds = try StrictJSON.decodeIfPresentDouble(
            container,
            "maxDurationSeconds"
        )
        self.init(
            enabled: enabled,
            maxIterations: maxIterations,
            maxDurationSeconds: maxDurationSeconds
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

        case .scroll(let direction, let amount):
            try container.encode("scroll", forKey: StrictCodingKey(stringValue: "type"))
            try container.encode(direction, forKey: StrictCodingKey(stringValue: "direction"))
            try container.encode(amount, forKey: StrictCodingKey(stringValue: "amount"))

        case .pageNavigate(let move):
            try container.encode("pageNavigate", forKey: StrictCodingKey(stringValue: "type"))
            try container.encode(move, forKey: StrictCodingKey(stringValue: "move"))

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
