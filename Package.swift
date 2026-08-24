// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Waypoint",
    platforms: [
        .macOS(.v13),
    ],
    products: [
        .library(name: "Domain", targets: ["Domain"]),
        .library(name: "Config", targets: ["Config"]),
        .library(name: "Safety", targets: ["Safety"]),
        .library(name: "CoreEngine", targets: ["CoreEngine"]),
        .library(name: "Actions", targets: ["Actions"]),
        .library(name: "Observability", targets: ["Observability"]),
        .library(name: "Accessibility", targets: ["Accessibility"]),
        .library(name: "InputSynthesis", targets: ["InputSynthesis"]),
        .library(name: "AppControl", targets: ["AppControl"]),
        .library(name: "Permissions", targets: ["Permissions"]),
        .library(name: "Adapters", targets: ["Adapters"]),
        .library(name: "Timing", targets: ["Timing"]),
    ],
    targets: [
        // Pure-logic modules — must not import AppKit / ApplicationServices.
        .target(name: "Domain", path: "Sources/Domain"),
        .target(
            name: "Config",
            dependencies: ["Domain"],
            path: "Sources/Config"
        ),
        .target(
            name: "Safety",
            dependencies: ["Domain"],
            path: "Sources/Safety"
        ),
        .target(
            name: "Observability",
            path: "Sources/Observability"
        ),
        .target(
            name: "CoreEngine",
            dependencies: ["Domain", "Safety", "Observability"],
            path: "Sources/CoreEngine"
        ),
        .target(name: "Timing", path: "Sources/Timing"),

        // Platform / interaction modules (stubs / simulation).
        .target(
            name: "Actions",
            dependencies: ["Domain", "CoreEngine"],
            path: "Sources/Actions"
        ),
        .target(name: "Accessibility", path: "Sources/Accessibility"),
        .target(name: "InputSynthesis", path: "Sources/InputSynthesis"),
        .target(
            name: "AppControl",
            dependencies: ["Domain"],
            path: "Sources/AppControl"
        ),
        .target(
            name: "Permissions",
            path: "Sources/Permissions"
        ),
        .target(name: "Adapters", path: "Sources/Adapters"),

        .testTarget(
            name: "DomainTests",
            dependencies: ["Domain"],
            path: "Tests/DomainTests"
        ),
        .testTarget(
            name: "ConfigTests",
            dependencies: ["Config", "Domain"],
            path: "Tests/ConfigTests"
        ),
        .testTarget(
            name: "SafetyTests",
            dependencies: ["Safety", "Domain"],
            path: "Tests/SafetyTests"
        ),
        .testTarget(
            name: "EngineTests",
            dependencies: ["CoreEngine", "Actions", "Domain", "Safety", "Observability"],
            path: "Tests/EngineTests"
        ),
        .testTarget(
            name: "AppControlTests",
            dependencies: ["AppControl", "Domain"],
            path: "Tests/AppControlTests"
        ),
        .testTarget(
            name: "PermissionsTests",
            dependencies: ["Permissions"],
            path: "Tests/PermissionsTests"
        ),
    ]
)
