/// Shared error taxonomy for Domain and higher layers.
public enum DomainError: Error, Equatable, Sendable {
    case permission(String)
    case precondition(String)
    case action(String)
    case forbidden(String)
    case timeout(String)
}
