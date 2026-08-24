/// How an action is physically performed at the platform layer.
public enum Primitive: Equatable, Sendable {
    case scrollWheel
    case inertKey
    case appControl
    case none
}
