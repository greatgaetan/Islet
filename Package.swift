// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "Islet",
    platforms: [.macOS("26.0")],
    targets: [
        // Pure logic: geometry, state machine, motion tokens.
        // No window, no view — runs and tests without launching a UI.
        .target(name: "IsletCore"),

        // AppKit shell + SwiftUI content.
        .executableTarget(name: "Islet", dependencies: ["IsletCore"]),

        .testTarget(name: "IsletCoreTests", dependencies: ["IsletCore"]),
    ]
)
