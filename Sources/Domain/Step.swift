public struct Step: Equatable, Sendable {
    public var action: ActionKind
    public var timeoutSeconds: Double
    public var retryPolicy: RetryPolicy
    public var onError: OnErrorBehavior

    public init(
        action: ActionKind,
        timeoutSeconds: Double,
        retryPolicy: RetryPolicy,
        onError: OnErrorBehavior
    ) {
        self.action = action
        self.timeoutSeconds = timeoutSeconds
        self.retryPolicy = retryPolicy
        self.onError = onError
    }
}

public struct RetryPolicy: Equatable, Sendable {
    public var maxRetries: Int

    public init(maxRetries: Int) {
        self.maxRetries = maxRetries
    }
}

public enum OnErrorBehavior: Equatable, Sendable {
    case retry
    case skip
    case abort
}
