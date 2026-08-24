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
        .target(name: "Config", path: "Sources/Config"),
        .target(name: "Safety", path: "Sources/Safety"),
        .target(name: "CoreEngine", path: "Sources/CoreEngine"),
        .target(name: "Timing", path: "Sources/Timing"),

        // Platform / interaction modules (stubs in this milestone).
        .target(name: "Actions", path: "Sources/Actions"),
        .target(name: "Observability", path: "Sources/Observability"),
        .target(name: "Accessibility", path: "Sources/Accessibility"),
        .target(name: "InputSynthesis", path: "Sources/InputSynthesis"),
        .target(name: "AppControl", path: "Sources/AppControl"),
        .target(name: "Permissions", path: "Sources/Permissions"),
        .target(name: "Adapters", path: "Sources/Adapters"),

        .testTarget(
            name: "DomainTests",
            dependencies: ["Domain"],
            path: "Tests/DomainTests"
        ),
    ]
)
