public struct TargetApp: Equatable, Sendable {
    public var bundleID: String
    public var classification: TargetAppClass

    public init(bundleID: String, classification: TargetAppClass) {
        self.bundleID = bundleID
        self.classification = classification
    }
}

public enum TargetAppClass: Equatable, Sendable {
    case browser
    case editor
    case finder
    case generic
}
