/// Caps used when configuring multi-press / scroll navigation (pure Domain).
public enum NavigationLimits {
    public static let maxArrowPresses = 20
    public static let maxScrollAmount = 100
    public static let minIntervalSeconds = 0.05
    public static let maxIntervalSeconds = 60.0
    /// Belt-and-suspenders ceiling when `untilStopped` (or huge iteration caps).
    public static let absoluteMaxIterations = 1_000_000
}
