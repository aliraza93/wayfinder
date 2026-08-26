import Foundation

/// Intelligent read-only browser navigation surface (Domain models).
/// Implementations live in Accessibility / Actions — this API never exposes
/// closeTab, closeWindow, reload, goBack, goForward, newTab, or omnibox control.
public protocol IntelligentBrowserNavigation: Sendable {
    func discoverWindows() -> [BrowserWindowDescriptor]
    func discoverTabs(in window: BrowserWindowDescriptor) -> [BrowserTabDescriptor]
    func inspectPage(in tab: BrowserTabDescriptor) -> WebPageSnapshot?
    func discoverNavigationTargets(in page: WebPageSnapshot) -> [WebNavCandidate]
}

/// Read-only window identity (no activation API).
public struct BrowserWindowDescriptor: Equatable, Sendable, Identifiable {
    public var id: String
    public var title: String
    public var bundleID: String

    public init(id: String, title: String, bundleID: String) {
        self.id = id
        self.title = title
        self.bundleID = bundleID
    }
}

/// Read-only tab identity — existing tabs only; never closed by automation.
public struct BrowserTabDescriptor: Equatable, Sendable, Identifiable {
    public var id: String
    public var title: String
    public var windowID: String

    public init(id: String, title: String, windowID: String) {
        self.id = id
        self.title = title
        self.windowID = windowID
    }
}
