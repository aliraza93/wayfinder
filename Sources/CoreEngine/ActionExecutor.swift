import Domain
import Foundation

public protocol ActionExecutor: Sendable {
    func execute(action: ActionKind, target: TargetApp) async throws
}
