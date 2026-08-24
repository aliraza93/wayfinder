public struct Workflow: Equatable, Sendable {
    public var name: String
    public var targets: [TargetApp]
    public var steps: [Step]
    public var loop: LoopSettings

    public init(
        name: String,
        targets: [TargetApp],
        steps: [Step],
        loop: LoopSettings
    ) {
        self.name = name
        self.targets = targets
        self.steps = steps
        self.loop = loop
    }
}

public struct LoopSettings: Equatable, Sendable {
    public var enabled: Bool
    /// Hard cap on loop iterations (inclusive of the first pass when enabled).
    public var maxIterations: Int
    /// Optional wall-clock cap for the whole run, in seconds.
    public var maxDurationSeconds: Double?

    public init(enabled: Bool, maxIterations: Int, maxDurationSeconds: Double? = nil) {
        self.enabled = enabled
        self.maxIterations = maxIterations
        self.maxDurationSeconds = maxDurationSeconds
    }
}
