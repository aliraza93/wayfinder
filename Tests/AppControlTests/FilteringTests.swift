import AppControl
import Domain
import XCTest

private struct FakeRunningAppsProvider: RunningAppsProvider {
    var apps: [RunningAppInfo]

    func runningApps() -> [RunningAppInfo] {
        apps
    }
}

final class FilteringTests: XCTestCase {
    func testFilterExcludesNonRegularHelpers() {
        let apps: [RunningAppInfo] = [
            RunningAppInfo(
                bundleID: "com.google.Chrome",
                displayName: "Google Chrome",
                activationPolicy: .regular,
                isActive: false
            ),
            RunningAppInfo(
                bundleID: "com.google.Chrome.helper",
                displayName: "Chrome Helper",
                activationPolicy: .accessory,
                isActive: false
            ),
            RunningAppInfo(
                bundleID: "com.microsoft.VSCode",
                displayName: "Code",
                activationPolicy: .regular,
                isActive: true
            ),
            RunningAppInfo(
                bundleID: nil,
                displayName: "Anonymous",
                activationPolicy: .regular,
                isActive: false
            ),
            RunningAppInfo(
                bundleID: "com.apple.Finder",
                displayName: "Finder",
                activationPolicy: .regular,
                isActive: false
            ),
            RunningAppInfo(
                bundleID: "com.example.agent",
                displayName: "Agent",
                activationPolicy: .prohibited,
                isActive: false
            ),
        ]

        let filtered = AppEnumerator.filterUserFacing(apps)
        let ids = filtered.compactMap(\.bundleID)
        XCTAssertEqual(
            ids,
            ["com.google.Chrome", "com.microsoft.VSCode", "com.apple.Finder"]
        )
    }

    func testIsRunningAndResolveByBundleID() {
        let provider = FakeRunningAppsProvider(apps: [
            RunningAppInfo(
                bundleID: "com.google.Chrome",
                displayName: "Google Chrome",
                activationPolicy: .regular,
                isActive: false
            ),
            RunningAppInfo(
                bundleID: "com.google.Chrome.helper",
                displayName: "Helper",
                activationPolicy: .accessory,
                isActive: false
            ),
        ])
        let enumerator = AppEnumerator(provider: provider)

        XCTAssertTrue(enumerator.isRunning(bundleID: "com.google.Chrome"))
        XCTAssertFalse(enumerator.isRunning(bundleID: "com.google.Chrome.helper"))
        XCTAssertFalse(enumerator.isRunning(bundleID: "com.apple.Safari"))

        let target = TargetApp(bundleID: "com.google.Chrome", classification: .browser)
        let resolved = enumerator.resolve(target)
        XCTAssertEqual(resolved?.bundleID, "com.google.Chrome")
        XCTAssertEqual(resolved?.displayName, "Google Chrome")

        let missing = TargetApp(bundleID: "com.apple.Safari", classification: .browser)
        XCTAssertNil(enumerator.resolve(missing))
    }

    func testFrontmostMappingIgnoresActiveHelper() {
        let apps: [RunningAppInfo] = [
            RunningAppInfo(
                bundleID: "com.google.Chrome.helper",
                displayName: "Helper",
                activationPolicy: .accessory,
                isActive: true
            ),
            RunningAppInfo(
                bundleID: "com.microsoft.VSCode",
                displayName: "Code",
                activationPolicy: .regular,
                isActive: false
            ),
        ]
        XCTAssertNil(FrontmostAppResolver.resolve(from: apps))

        let withRegularFront: [RunningAppInfo] = [
            RunningAppInfo(
                bundleID: "com.apple.Finder",
                displayName: "Finder",
                activationPolicy: .regular,
                isActive: true
            ),
            RunningAppInfo(
                bundleID: "com.google.Chrome",
                displayName: "Google Chrome",
                activationPolicy: .regular,
                isActive: false
            ),
        ]
        let front = FrontmostAppResolver.resolve(from: withRegularFront)
        XCTAssertEqual(front?.bundleID, "com.apple.Finder")
        XCTAssertEqual(front?.displayName, "Finder")
    }

    func testFrontmostViaProvider() {
        let provider = FakeRunningAppsProvider(apps: [
            RunningAppInfo(
                bundleID: "com.google.Chrome",
                displayName: "Google Chrome",
                activationPolicy: .regular,
                isActive: true
            ),
        ])
        let resolver = FrontmostAppResolver(provider: provider)
        XCTAssertEqual(resolver.frontmostApp()?.bundleID, "com.google.Chrome")
    }
}
