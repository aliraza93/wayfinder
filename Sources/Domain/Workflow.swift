public struct Workflow: Equatable, Sendable {
    public var name: String
    public var targets: [TargetApp]
    public var steps: [Step]
    public var loop: LoopSettings
    /// Existing workspace files (legacy field; prefer `review.filePaths`).
    public var reviewFilePaths: [String]
    /// Single Read & Review Workspace session configuration.
    public var review: ReviewWorkspaceSettings

    public init(
        name: String,
        targets: [TargetApp],
        steps: [Step],
        loop: LoopSettings,
        reviewFilePaths: [String] = [],
        review: ReviewWorkspaceSettings = .default
    ) {
        self.name = name
        self.targets = targets
        self.steps = steps
        self.loop = loop
        self.reviewFilePaths = reviewFilePaths
        self.review = review
    }
}

public struct LoopSettings: Equatable, Sendable {
    public var enabled: Bool
    /// Hard cap on loop iterations (inclusive of the first pass when enabled).
    /// Ignored as a stop condition when `maxDurationSeconds` or `untilStopped` is set
    /// (only an absolute safety ceiling applies then).
    public var maxIterations: Int
    /// Optional wall-clock cap for the whole run, in seconds.
    public var maxDurationSeconds: Double?
    /// When true, ignore `maxIterations` and run until stop or `maxDurationSeconds`.
    /// A safety ceiling still applies in the engine.
    public var untilStopped: Bool
    /// When true, each loop iteration runs steps in a fresh random order.
    public var shuffleSteps: Bool

    public init(
        enabled: Bool,
        maxIterations: Int,
        maxDurationSeconds: Double? = nil,
        untilStopped: Bool = false,
        shuffleSteps: Bool = false
    ) {
        self.enabled = enabled
        self.maxIterations = maxIterations
        self.maxDurationSeconds = maxDurationSeconds
        self.untilStopped = untilStopped
        self.shuffleSteps = shuffleSteps
    }
}
