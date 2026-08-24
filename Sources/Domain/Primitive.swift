/// How an action is physically performed at the platform layer.
public enum Primitive: Equatable, Sendable {
    case scrollWheel
    case inertKey
    /// Allowlisted modifier+key chords used only for navigation (tabs, selection highlight).
    case navigationChord
    /// Adapter-resolved click inside the target app’s content area (never arbitrary desktop).
    case targetedClick
    case appControl
    case none
}
