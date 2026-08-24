/// Safety metadata for an `ActionKind`. Looked up via an exhaustive switch.
public struct CapabilityTags: Equatable, Sendable {
    public let mutatesText: Bool
    public let requiresFocusGuard: Bool
    public let verifiable: Bool
    public let primitive: Primitive

    public init(
        mutatesText: Bool,
        requiresFocusGuard: Bool,
        verifiable: Bool,
        primitive: Primitive
    ) {
        self.mutatesText = mutatesText
        self.requiresFocusGuard = requiresFocusGuard
        self.verifiable = verifiable
        self.primitive = primitive
    }
}

public extension ActionKind {
    /// Capability tags for this action. Exhaustive — adding a case forces a tag decision.
    var capabilityTags: CapabilityTags {
        switch self {
        case .activateApp:
            return CapabilityTags(
                mutatesText: false,
                requiresFocusGuard: false,
                verifiable: true,
                primitive: .appControl
            )
        case .switchWindow:
            return CapabilityTags(
                mutatesText: false,
                requiresFocusGuard: true,
                verifiable: true,
                primitive: .appControl
            )
        case .switchTab:
            return CapabilityTags(
                mutatesText: false,
                requiresFocusGuard: true,
                verifiable: false,
                primitive: .navigationChord
            )
        case .scroll:
            return CapabilityTags(
                mutatesText: false,
                requiresFocusGuard: true,
                verifiable: false,
                primitive: .scrollWheel
            )
        case .pageNavigate:
            return CapabilityTags(
                mutatesText: false,
                requiresFocusGuard: true,
                verifiable: false,
                primitive: .inertKey
            )
        case .arrowNavigate:
            return CapabilityTags(
                mutatesText: false,
                requiresFocusGuard: true,
                verifiable: false,
                primitive: .inertKey
            )
        case .highlightNavigate:
            return CapabilityTags(
                mutatesText: false,
                requiresFocusGuard: true,
                verifiable: false,
                primitive: .navigationChord
            )
        case .contentClick:
            return CapabilityTags(
                mutatesText: false,
                requiresFocusGuard: true,
                verifiable: false,
                primitive: .targetedClick
            )
        case .explorerFileSwitch:
            return CapabilityTags(
                mutatesText: false,
                requiresFocusGuard: true,
                verifiable: false,
                primitive: .navigationChord
            )
        case .openExistingFile:
            return CapabilityTags(
                mutatesText: false,
                requiresFocusGuard: false,
                verifiable: true,
                primitive: .appControl
            )
        case .wait:
            return CapabilityTags(
                mutatesText: false,
                requiresFocusGuard: false,
                verifiable: false,
                primitive: .none
            )
        case .returnToPrevious:
            return CapabilityTags(
                mutatesText: false,
                requiresFocusGuard: false,
                verifiable: true,
                primitive: .appControl
            )
        }
    }
}
